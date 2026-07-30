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
  assert.match(html, /今天，先把重要的事放在眼前。/);
  assert.match(html, /月历/);
  assert.match(html, /日程/);
  assert.match(html, /日记/);
  assert.match(html, /AI 助手/);
  assert.match(html, /\/assets\/xigua-teacher\.png/);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape/);
});

test("keeps local data and AI privacy guardrails in source", async () => {
  const [page, layout, packageJson] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../package.json", import.meta.url), "utf8"),
  ]);

  assert.match(page, /xigua-personal-desk-v1/);
  assert.match(page, /localStorage/);
  assert.match(page, /api\.deepseek\.com\/chat\/completions/);
  assert.match(page, /不得编造人物、地点、情节、时间、因果或心理活动/);
  assert.match(page, /apiKey:\s*""/);
  assert.match(layout, /og\.png/);
  assert.match(packageJson, /"name": "xigua-personal-workbench"/);
  assert.doesNotMatch(packageJson, /react-loading-skeleton/);
  await access(new URL("../public/og.png", import.meta.url));
  await access(new URL("../public/assets/xigua-teacher.png", import.meta.url));
});
