const test = require("node:test");
const assert = require("node:assert/strict");
const { once } = require("node:events");
const { bytes, duration, systemSnapshot, createServer } = require("../server");

test("formats bytes and durations for the UI", () => {
  assert.equal(bytes(1024), "1 KB");
  assert.equal(bytes(5 * 1024 ** 3), "5.0 GB");
  assert.equal(duration(90061), "1d 1h");
});

test("system snapshot has usable live values", () => {
  const snapshot = systemSnapshot();
  assert.ok(snapshot.hostname);
  assert.ok(snapshot.cores >= 1);
  assert.ok(snapshot.memory.total > 0);
  assert.ok(snapshot.memory.usedPercent >= 0 && snapshot.memory.usedPercent <= 100);
  assert.ok(Array.isArray(snapshot.networks));
});

test("HTTP server serves the app and validates unsafe input", async (t) => {
  const server = createServer().listen(0, "127.0.0.1");
  await once(server, "listening");
  t.after(() => server.closeAllConnections());
  t.after(() => server.close());
  const { port } = server.address();

  const page = await fetch(`http://127.0.0.1:${port}/`);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /NetLens/);

  const system = await fetch(`http://127.0.0.1:${port}/api/system`);
  assert.equal(system.status, 200);
  assert.ok((await system.json()).hostname);

  const invalidDomain = await fetch(`http://127.0.0.1:${port}/api/diagnostics?domain=not_valid`);
  assert.equal(invalidDomain.status, 400);

  const invalidPort = await fetch(`http://127.0.0.1:${port}/api/port?port=70000`);
  assert.equal(invalidPort.status, 400);

  const traversal = await fetch(`http://127.0.0.1:${port}/..%2Fserver.js`);
  assert.ok([403, 404].includes(traversal.status));
});
