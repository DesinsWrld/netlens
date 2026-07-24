const state = { loadHistory: Array(18).fill(0) };
const $ = (selector) => document.querySelector(selector);

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function toast(message) {
  const element = $("#toast");
  element.textContent = message;
  element.classList.add("show");
  setTimeout(() => element.classList.remove("show"), 2200);
}

function renderChart(value) {
  state.loadHistory.push(value);
  state.loadHistory = state.loadHistory.slice(-18);
  const max = Math.max(1, ...state.loadHistory);
  const points = state.loadHistory.map((item, index) => {
    const x = 30 + (index / (state.loadHistory.length - 1)) * 670;
    const y = 180 - (item / max) * 135;
    return [x, y];
  });
  const line = points.map(([x, y], index) => `${index ? "L" : "M"}${x.toFixed(1)} ${y.toFixed(1)}`).join(" ");
  $("#line-path").setAttribute("d", line);
  $("#area-path").setAttribute("d", `${line} L700 180 L30 180 Z`);
}

function memoryStatus(percent) {
  if (percent >= 90) return ["High", "var(--red)"];
  if (percent >= 75) return ["Elevated", "#e99c2d"];
  return ["Healthy", "var(--green)"];
}

async function refreshSystem(showNotice = false) {
  try {
    const response = await fetch("/api/system");
    if (!response.ok) throw new Error("System endpoint failed");
    const data = await response.json();
    const [label, color] = memoryStatus(data.memory.usedPercent);
    $("#memory-status").textContent = label;
    $("#memory-status").style.color = color;
    $("#memory-percent").textContent = `${data.memory.usedPercent}%`;
    $("#memory-bar").style.width = `${data.memory.usedPercent}%`;
    $("#memory-bar").style.background = color;
    $("#memory-detail").textContent = `${data.memory.usedLabel} of ${data.memory.totalLabel} in use`;
    $("#cores").textContent = data.cores;
    $("#cpu").textContent = data.cpu;
    $("#uptime").textContent = data.uptimeLabel;
    $("#platform").textContent = `${data.platform} · ${data.architecture}`;
    $("#adapter-count").textContent = data.networks.length;
    $("#hostname").textContent = data.hostname;
    $("#load-value").textContent = data.load[0].toFixed(2);
    renderChart(data.load[0]);
    $("#network-list").innerHTML = data.networks.length
      ? data.networks.map((item) => `
        <div class="network-item">
          <header><b>${escapeHtml(item.name)}</b><span>${escapeHtml(item.address)}</span></header>
          <small>Mask ${escapeHtml(item.netmask)} · MAC ${escapeHtml(item.mac)}</small>
        </div>`).join("")
      : `<div class="result-placeholder">No active non-local IPv4 adapter found.</div>`;
    $("#last-updated").textContent = `Updated ${new Date(data.timestamp).toLocaleTimeString()}`;
    if (showNotice) toast("System data refreshed");
  } catch {
    toast("Could not read system data");
  }
}

function resultMarkup(data) {
  return `<div class="result-grid">
    <div><small>DNS</small><strong class="${data.dns.ok ? "ok" : "bad"}">${data.dns.ok ? "Resolved" : "Failed"}</strong></div>
    <div><small>Address</small><strong>${escapeHtml(data.dns.address || "Unavailable")}</strong></div>
    <div><small>HTTPS :443</small><strong class="${data.https.ok ? "ok" : "bad"}">${data.https.ok ? `Open · ${data.https.latencyMs}ms` : "Unavailable"}</strong></div>
  </div>`;
}

async function runDiagnostic(domain, target) {
  target.className = "diagnostic-result muted";
  target.textContent = "Running DNS and HTTPS checks…";
  try {
    const response = await fetch(`/api/diagnostics?domain=${encodeURIComponent(domain)}`);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    target.className = "diagnostic-result";
    target.innerHTML = resultMarkup(data);
  } catch (error) {
    target.className = "diagnostic-result bad";
    target.textContent = error.message || "Diagnostic failed.";
  }
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll(".nav-item, .view").forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    $(`#${button.dataset.view}-view`).classList.add("active");
    const copy = {
      overview: ["System overview", "A live readout of this computer and its active network."],
      diagnostics: ["Network diagnostics", "Focused checks for public connectivity and local services."],
      about: ["About NetLens", "The thinking, technology, and privacy choices behind the app."]
    };
    [$("#page-title").textContent, $("#subtitle").textContent] = copy[button.dataset.view];
  });
});

$("#refresh").addEventListener("click", () => refreshSystem(true));
$("#quick-form").addEventListener("submit", (event) => {
  event.preventDefault();
  runDiagnostic($("#domain").value.trim(), $("#quick-result"));
});
$("#diagnostic-form").addEventListener("submit", (event) => {
  event.preventDefault();
  runDiagnostic($("#diagnostic-domain").value.trim(), $("#diagnostic-result"));
});
$("#port-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const target = $("#port-result");
  target.textContent = "Checking localhost…";
  try {
    const response = await fetch(`/api/port?port=${encodeURIComponent($("#port").value)}`);
    const data = await response.json();
    if (!response.ok) throw new Error(data.error);
    target.className = `diagnostic-result ${data.ok ? "ok" : "bad"}`;
    target.innerHTML = `<strong>${data.ok ? "Service is listening" : "No service detected"}</strong><span>127.0.0.1:${data.port} · ${data.latencyMs}ms${data.error ? ` · ${escapeHtml(data.error)}` : ""}</span>`;
  } catch (error) {
    target.className = "diagnostic-result bad";
    target.textContent = error.message;
  }
});

refreshSystem();
setInterval(() => refreshSystem(), 5000);
