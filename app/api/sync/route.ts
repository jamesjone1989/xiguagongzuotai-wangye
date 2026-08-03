import { headers } from "next/headers";

type CloudState = {
  tasks: unknown[];
  monthlyNotes: unknown[];
  diaries: unknown[];
  messages: unknown[];
  diaryMessages: unknown[];
};

const TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS workbench_sync (
    user_id TEXT PRIMARY KEY NOT NULL,
    payload TEXT NOT NULL,
    updated_at INTEGER NOT NULL
  )
`;

async function database() {
  const { env } = await import("cloudflare:workers");
  const binding = (env as unknown as { DB?: D1Database }).DB;
  if (!binding) throw new Error("D1 binding is unavailable");
  return binding;
}

async function userId() {
  const requestHeaders = await headers();
  return requestHeaders.get("oai-authenticated-user-id");
}

function response(body: unknown, status = 200) {
  return Response.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function cloudState(value: unknown): CloudState | null {
  if (!value || typeof value !== "object") return null;
  const candidate = value as Partial<CloudState>;
  if (
    !Array.isArray(candidate.tasks) ||
    !Array.isArray(candidate.monthlyNotes) ||
    !Array.isArray(candidate.diaries) ||
    !Array.isArray(candidate.messages) ||
    !Array.isArray(candidate.diaryMessages)
  ) {
    return null;
  }
  return {
    tasks: candidate.tasks,
    monthlyNotes: candidate.monthlyNotes,
    diaries: candidate.diaries,
    messages: candidate.messages,
    diaryMessages: candidate.diaryMessages,
  };
}

async function ensureTable(db: D1Database) {
  await db.prepare(TABLE_SQL).run();
}

export async function GET() {
  const currentUserId = await userId();
  if (!currentUserId) return response({ error: "需要先登录 ChatGPT 才能同步" }, 401);

  try {
    const db = await database();
    await ensureTable(db);
    const row = await db
      .prepare("SELECT payload, updated_at FROM workbench_sync WHERE user_id = ?1")
      .bind(currentUserId)
      .first<{ payload: string; updated_at: number }>();
    if (!row) return response({ state: null, updatedAt: 0 });

    const state = cloudState(JSON.parse(row.payload));
    if (!state) return response({ state: null, updatedAt: row.updated_at });
    return response({ state, updatedAt: row.updated_at });
  } catch {
    return response({ error: "云端同步暂时不可用" }, 503);
  }
}

export async function POST(request: Request) {
  const currentUserId = await userId();
  if (!currentUserId) return response({ error: "需要先登录 ChatGPT 才能同步" }, 401);

  try {
    const body = (await request.json()) as {
      state?: unknown;
      clientUpdatedAt?: unknown;
    };
    const state = cloudState(body.state);
    if (!state) return response({ error: "同步数据格式不正确" }, 400);

    const payload = JSON.stringify(state);
    if (payload.length > 900_000) return response({ error: "同步数据过大" }, 413);

    const db = await database();
    await ensureTable(db);
    const existing = await db
      .prepare("SELECT payload, updated_at FROM workbench_sync WHERE user_id = ?1")
      .bind(currentUserId)
      .first<{ payload: string; updated_at: number }>();
    const clientUpdatedAt = Number(body.clientUpdatedAt) || 0;
    if (existing && existing.updated_at > clientUpdatedAt) {
      const remoteState = cloudState(JSON.parse(existing.payload));
      return response(
        { state: remoteState, updatedAt: existing.updated_at, conflict: true },
        409,
      );
    }

    const updatedAt = Date.now();
    await db
      .prepare(
        `INSERT INTO workbench_sync (user_id, payload, updated_at)
         VALUES (?1, ?2, ?3)
         ON CONFLICT(user_id) DO UPDATE SET
           payload = excluded.payload,
           updated_at = excluded.updated_at`,
      )
      .bind(currentUserId, payload, updatedAt)
      .run();
    return response({ state, updatedAt });
  } catch {
    return response({ error: "云端同步暂时不可用" }, 503);
  }
}
