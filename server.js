const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const dns = require("node:dns").promises;
const net = require("node:net");
const { performance } = require("node:perf_hooks");

const PUBLIC_DIR = path.join(__dirname, "public");
const PORT = Number(process.env.PORT) || 4173;
const HOST = process.env.HOST || "127.0.0.1";

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "application/javascript; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png"
};

function bytes(value) {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = value;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  return `${size.toFixed(unit > 1 ? 1 : 0)} ${units[unit]}`;
}

function duration(seconds) {
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);
  return days ? `${days}d ${hours}h` : `${hours}h ${mins}m`;
}

function networkDetails() {
  let interfaces = {};
  try {
    interfaces = os.networkInterfaces();
  } catch {
    return [];
  }
  const active = [];
  for (const [name, entries = []] of Object.entries(interfaces)) {
    for (const item of entries) {
      if (!item.internal && item.family === "IPv4") {
        active.push({ name, address: item.address, netmask: item.netmask, mac: item.mac });
      }
    }
  }
  return active;
}

function systemSnapshot() {
  const total = os.totalmem();
  const free = os.freemem();
  const cpus = os.cpus();
  let uptime = process.uptime();
  try {
    uptime = os.uptime();
  } catch {
    // Sandboxed runtimes can deny host uptime while still allowing app uptime.
  }
  return {
    hostname: os.hostname(),
    platform: `${os.type()} ${os.release()}`,
    architecture: os.arch(),
    cpu: cpus[0]?.model?.trim() || "Unknown processor",
    cores: cpus.length,
    load: os.loadavg().map((value) => Number(value.toFixed(2))),
    memory: {
      total,
      free,
      used: total - free,
      usedPercent: Math.round(((total - free) / total) * 100),
      totalLabel: bytes(total),
      usedLabel: bytes(total - free)
    },
    uptime,
    uptimeLabel: duration(uptime),
    networks: networkDetails(),
    timestamp: new Date().toISOString()
  };
}

async function timedDnsLookup(hostname) {
  const start = performance.now();
  try {
    const result = await dns.lookup(hostname);
    return {
      ok: true,
      hostname,
      address: result.address,
      latencyMs: Math.max(1, Math.round(performance.now() - start))
    };
  } catch (error) {
    return { ok: false, hostname, error: error.code || "LOOKUP_FAILED" };
  }
}

function checkPort(host, port, timeout = 1500) {
  return new Promise((resolve) => {
    const start = performance.now();
    const socket = net.createConnection({ host, port });
    const finish = (ok, error) => {
      socket.destroy();
      resolve({
        host,
        port,
        ok,
        latencyMs: Math.max(1, Math.round(performance.now() - start)),
        ...(error ? { error } : {})
      });
    };
    socket.setTimeout(timeout);
    socket.once("connect", () => finish(true));
    socket.once("timeout", () => finish(false, "TIMEOUT"));
    socket.once("error", (error) => finish(false, error.code || "CONNECTION_FAILED"));
  });
}

function sendJson(response, status, payload) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff"
  });
  response.end(JSON.stringify(payload));
}

async function handleApi(request, response, url) {
  if (request.method !== "GET") {
    sendJson(response, 405, { error: "Method not allowed" });
    return;
  }
  if (url.pathname === "/api/system") {
    sendJson(response, 200, systemSnapshot());
    return;
  }
  if (url.pathname === "/api/diagnostics") {
    const domain = (url.searchParams.get("domain") || "example.com").trim().toLowerCase();
    if (!/^(?=.{1,253}$)([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(domain)) {
      sendJson(response, 400, { error: "Enter a valid public domain, such as example.com." });
      return;
    }
    const [dnsResult, httpsResult] = await Promise.all([
      timedDnsLookup(domain),
      checkPort(domain, 443)
    ]);
    sendJson(response, 200, {
      domain,
      dns: dnsResult,
      https: httpsResult,
      checkedAt: new Date().toISOString()
    });
    return;
  }
  if (url.pathname === "/api/port") {
    const port = Number(url.searchParams.get("port"));
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      sendJson(response, 400, { error: "Port must be a number from 1 to 65535." });
      return;
    }
    sendJson(response, 200, await checkPort("127.0.0.1", port));
    return;
  }
  sendJson(response, 404, { error: "Not found" });
}

function serveStatic(response, pathname) {
  const requested = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const filePath = path.resolve(PUBLIC_DIR, requested);
  if (!filePath.startsWith(`${PUBLIC_DIR}${path.sep}`)) {
    response.writeHead(403);
    response.end("Forbidden");
    return;
  }
  fs.readFile(filePath, (error, data) => {
    if (error) {
      response.writeHead(error.code === "ENOENT" ? 404 : 500);
      response.end(error.code === "ENOENT" ? "Not found" : "Server error");
      return;
    }
    response.writeHead(200, {
      "Content-Type": mimeTypes[path.extname(filePath)] || "application/octet-stream",
      "X-Content-Type-Options": "nosniff"
    });
    response.end(data);
  });
}

function createServer() {
  return http.createServer(async (request, response) => {
    const url = new URL(request.url, `http://${request.headers.host || "localhost"}`);
    if (url.pathname.startsWith("/api/")) {
      await handleApi(request, response, url);
    } else {
      serveStatic(response, url.pathname);
    }
  });
}

if (require.main === module) {
  createServer().listen(PORT, HOST, () => {
    console.log(`NetLens is running at http://${HOST}:${PORT}`);
  });
}

module.exports = { bytes, duration, systemSnapshot, checkPort, createServer };
