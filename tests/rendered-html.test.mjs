import assert from "node:assert/strict";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("http://localhost/", {
      headers: { accept: "text/html" },
    }),
    {
      ASSETS: {
        fetch: async () => new Response("Not found", { status: 404 }),
      },
    },
    {
      waitUntil() {},
      passThroughOnException() {},
    },
  );
}

test("server-renders the personal workbench", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>西瓜老师·个人工作台<\/title>/);
  assert.match(html, /今天要做什么？/);
  assert.match(html, /帮我安排/);
  assert.match(html, /收件箱/);
  assert.equal((html.match(/class="hour-line"/g) || []).length, 18);
  assert.match(html, /拖动卡片上下边缘，可以调整时长/);
  assert.match(html, /月历/);
  assert.match(html, /年历/);
  assert.match(html, /日程/);
  assert.match(html, /日记/);
  assert.doesNotMatch(html, /AI 助手/);
  assert.match(html, /\/assets\/xigua-teacher-user-cutout\.png/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("keeps local data and AI privacy guardrails in source", async () => {
  const [page, layout, styles, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /xigua-personal-desk-v1/);
  assert.match(page, /localStorage/);
  assert.match(page, /diaryMessages/);
  assert.match(page, /生成日记/);
  assert.match(page, /dayTasks\.slice\(0,\s*3\)/);
  assert.match(page, /LEGACY_SEED_TASK_IDS/);
  assert.match(page, /function compareTasks/);
  assert.match(page, /结束时间需要晚于开始时间/);
  assert.match(page, /aria-modal="true"/);
  assert.match(page, /monthlyNotes/);
  assert.match(page, /收件箱/);
  assert.match(page, /positionOverlappingTasks/);
  assert.match(page, /text\/x-workbench-task/);
  assert.match(page, /beginTaskResize/);
  assert.match(page, /today-hour-grid/);
  assert.match(page, /extractTodayTasks/);
  assert.match(page, /scheduledSelectedTasks/);
  assert.match(page, /没有具体时间时 start 和 end 都为空字符串/);
  assert.match(page, /AI 帮我填写/);
  assert.match(page, /已完成/);
  assert.match(page, /不填时间＝放入收件箱/);
  assert.match(page, /api\.deepseek\.com\/chat\/completions/);
  assert.match(page, /不得编造人物、地点、情节、时间、因果或心理活动/);
  assert.match(page, /apiKey:\s*""/);
  assert.match(layout, /og\.png/);
  assert.match(styles, /\.task-modal \{[\s\S]*max-height: calc\(100dvh - 32px\)/);
  assert.match(
    styles,
    /\.task-modal \.field-grid \{[\s\S]*grid-template-columns: 1\.25fr 0\.8fr 1fr 1fr/,
  );
  assert.match(packageJson, /"name": "xigua-personal-workbench"/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  await access(new URL("../public/og.png", import.meta.url));
  await access(
    new URL("../public/assets/xigua-teacher-user-cutout.png", import.meta.url),
  );
  await access(new URL("../public/fonts/OPPOSans-Regular.ttf", import.meta.url));
});
