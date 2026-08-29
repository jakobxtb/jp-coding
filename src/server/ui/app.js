const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
let cur = null, busy = false, models = { curated: [], all: [], current: "" };
let attached = [], skillsCache = [];

const api = async (u, o) => {
  const r = await fetch(u, o);
  if (!r.ok) { let e; try { e = (await r.json()).error } catch {} throw new Error(e || ("HTTP " + r.status)) }
  return r.json();
};
function toast(m, bad) {
  const t = $("#toast"); t.textContent = m;
  t.className = "glass on" + (bad ? " bad" : "");
  clearTimeout(t._t); t._t = setTimeout(() => t.className = "glass", bad ? 6000 : 2600);
}
const esc = s => String(s ?? "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const base = p => (p || "").split("/").filter(Boolean).pop() || p;
const PH = "CB";

function md(src) {
  const blocks = [];
  let s = esc(src).replace(/```(\w*)\n?([\s\S]*?)```/g, (m, l, c) => {
    blocks.push(c.replace(/\n$/, "")); return "\n" + PH + (blocks.length - 1) + "\n";
  });
  s = s.replace(/`([^`\n]+)`/g, "<code>$1</code>")
       .replace(/^### (.+)$/gm, "<h3>$1</h3>")
       .replace(/^## (.+)$/gm, "<h2>$1</h2>")
       .replace(/^# (.+)$/gm, "<h1>$1</h1>")
       .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
       .replace(/\[([^\]]+)\]\((https?:[^)\s]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
  const out = []; let ul = null;
  for (const line of s.split("\n")) {
    const li = line.match(/^\s*[-*]\s+(.*)$/);
    if (li) { if (!ul) ul = []; ul.push("<li>" + li[1] + "</li>"); continue }
    if (ul) { out.push("<ul>" + ul.join("") + "</ul>"); ul = null }
    if (!line.trim()) continue;
    if (line.startsWith(PH) || /^<(h[123]|ul|pre)/.test(line)) { out.push(line); continue }
    out.push("<p>" + line + "</p>");
  }
  if (ul) out.push("<ul>" + ul.join("") + "</ul>");
  return out.join("\n").replace(new RegExp(PH + "(\\d+)", "g"), (m, i) => "<pre><code>" + blocks[+i] + "</code></pre>");
}

/* ---------------- status ---------------- */
async function refreshStatus() {
  try {
    const s = await api("/api/status");
    $("#dot").className = "dot " + (s.proxy ? "ok" : "no");
    $("#proxytxt").textContent = s.proxy ? "online" : "offline";
    $("#skills").textContent = s.skills;
    $("#store").textContent = s.data_dir.includes(".app/") ? "Paket" : "App Support";
    return s;
  } catch {
    $("#dot").className = "dot no"; $("#proxytxt").textContent = "offline";
    return null;
  }
}

const short = m => m.replace("claude-3-freecc-no-thinking/", "[fast] ")
                    .replace("anthropic/", "").replace("nvidia_nim/", "");

async function loadModels() {
  models = await api("/api/models");
  const sel = $("#model"); sel.innerHTML = "";
  const mk = (v, g) => { const o = document.createElement("option"); o.value = v; o.textContent = short(v); g.appendChild(o) };
  if (models.curated.length) {
    const g1 = document.createElement("optgroup"); g1.label = "Getestet und funktionierend";
    models.curated.forEach(m => mk(m, g1)); sel.appendChild(g1);
  }
  const rest = models.all.filter(m => !models.curated.includes(m) && m.startsWith("anthropic/"));
  if (rest.length) {
    const g2 = document.createElement("optgroup"); g2.label = "Alle uebrigen (" + rest.length + ", ungetestet)";
    rest.forEach(m => mk(m, g2)); sel.appendChild(g2);
  }
  const want = (cur && cur.model) || models.current;
  if (want && ![...sel.options].some(o => o.value === want)) {
    const g0 = document.createElement("optgroup"); g0.label = "Aktuell";
    mk(want, g0); sel.insertBefore(g0, sel.firstChild);
  }
  sel.value = want;
}

/* ---------------- chats ---------------- */
async function loadChats() {
  const list = await api("/api/chats");
  const box = $("#chats"); box.innerHTML = "";
  if (!list.length) {
    box.innerHTML = '<div style="padding:14px;font-size:11px;color:var(--muted)">Noch keine Chats.</div>';
    return;
  }
  list.forEach(c => {
    const d = document.createElement("div");
    d.className = "chat" + (cur && cur.id === c.id ? " on" : "");
    const t = document.createElement("div"); t.className = "t"; t.textContent = c.title || "Chat";
    const s = document.createElement("div"); s.className = "d";
    s.textContent = base(c.cwd) + "  " + (c.updated || "");
    const x = document.createElement("div"); x.className = "x"; x.textContent = "×";
    d.append(t, s, x);
    d.onclick = e => { if (e.target === x) { del(c.id) } else { openChat(c.id) } };
    box.appendChild(d);
  });
}
async function del(id) {
  await api("/api/chat/" + id + "/delete", { method: "POST" });
  if (cur && cur.id === id) { cur = null; render() }
  loadChats();
}
async function openChat(id) {
  cur = await api("/api/chat/" + id);
  await loadModels();
  $("#perm").value = cur.permission || "bypassPermissions";
  render(); loadChats();
}

function render() {
  const box = $("#msgs"), pill = $("#cwdpill");
  $("#cwd").textContent = cur ? base(cur.cwd) : "—";
  pill.title = cur ? cur.cwd : "Kein Chat geoeffnet";
  if (!cur) {
    box.innerHTML = '<div class="empty"><div class="logo">JP CODING</div>' +
      '<p>Kein Chat geoeffnet.<br>Starte mit <span class="kbd">+ NEUER CHAT</span> und waehle den Ordner, in dem gearbeitet werden soll.</p>' +
      '<p style="opacity:.65">Laeuft ueber deinen lokalen NVIDIA-NIM-Proxy.<br>Vollstaendig getrennt vom echten Claude.</p></div>';
    return;
  }
  box.innerHTML = "";
  cur.messages.forEach(m => box.appendChild(bubble(m)));
  box.scrollTop = box.scrollHeight;
}

function bubble(m) {
  const d = document.createElement("div");
  d.className = "m " + (m.role === "user" ? "user" : "ai");
  const role = document.createElement("div"); role.className = "role";
  role.innerHTML = '<span class="tag">' + (m.role === "user" ? "DU" : "JP") + "</span>" + esc(m.ts || "");
  d.appendChild(role);
  if ((m.files || []).length) {
    const fb = document.createElement("div");
    m.files.forEach(f => {
      const s = document.createElement("span"); s.className = "filechip";
      s.textContent = base(f); s.title = f; fb.appendChild(s);
    });
    d.appendChild(fb);
  }
  const body = document.createElement("div"); body.className = "body";
  if (m.role === "user") body.textContent = m.text; else body.innerHTML = md(m.text || "");
  d.appendChild(body);
  if ((m.tools || []).length) {
    const tb = document.createElement("div");
    m.tools.forEach(t => { const s = document.createElement("span"); s.className = "tool"; s.innerHTML = "<b>" + esc(t) + "</b>"; tb.appendChild(s) });
    d.appendChild(tb);
  }
  return d;
}

/* ---------------- attachments ---------------- */
function renderAttach() {
  const bar = $("#attachbar"); bar.innerHTML = "";
  attached.forEach((f, i) => {
    const s = document.createElement("span"); s.className = "filechip"; s.title = f;
    const n = document.createElement("span"); n.textContent = base(f);
    const x = document.createElement("span"); x.className = "rm"; x.textContent = "×";
    x.onclick = () => { attached.splice(i, 1); renderAttach() };
    s.append(n, x); bar.appendChild(s);
  });
}
$("#attach").onclick = async () => {
  try {
    const r = await api("/api/pick-files", { method: "POST" });
    if (r.cancelled) return;
    r.files.forEach(f => { if (!attached.includes(f)) attached.push(f) });
    renderAttach();
  } catch (e) { toast(e.message, true) }
};

/* ---------------- send ---------------- */
const ta = $("#input");
ta.addEventListener("input", () => { ta.style.height = "auto"; ta.style.height = Math.min(ta.scrollHeight, 190) + "px" });
ta.addEventListener("keydown", e => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send() } });
$("#send").onclick = send;
$("#stop").onclick = async () => {
  if (!cur) return;
  await api("/api/chat/" + cur.id + "/stop", { method: "POST" }).catch(() => {});
  toast("Abgebrochen");
};

async function send() {
  if (busy) return;
  const text = ta.value.trim();
  if (!text && !attached.length) return;
  if (!cur) return toast("Erst einen Chat anlegen", true);
  busy = true; $("#send").style.display = "none"; $("#stop").style.display = "";
  const files = attached.slice(); attached = []; renderAttach();
  ta.value = ""; ta.style.height = "auto";

  const box = $("#msgs");
  box.appendChild(bubble({ role: "user", text, files, ts: new Date().toTimeString().slice(0, 5) }));
  const wrap = document.createElement("div"); wrap.className = "m ai";
  wrap.innerHTML = '<div class="role"><span class="tag">JP</span>laeuft...</div>' +
                   '<div class="body"><span class="cursor"></span></div><div class="tools"></div>';
  box.appendChild(wrap); box.scrollTop = box.scrollHeight;
  const body = wrap.querySelector(".body"), toolbox = wrap.querySelector(".tools");
  let acc = "";

  try {
    const res = await fetch("/api/chat/" + cur.id + "/send", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ text, files, model: $("#model").value, permission: $("#perm").value })
    });
    if (!res.ok) { let m; try { m = (await res.json()).error } catch {} throw new Error(m || ("HTTP " + res.status)) }
    const rd = res.body.getReader(), dec = new TextDecoder(); let buf = "";
    for (;;) {
      const { value, done } = await rd.read(); if (done) break;
      buf += dec.decode(value, { stream: true });
      const parts = buf.split("\n\n"); buf = parts.pop();
      for (const p of parts) {
        const line = p.split("\n").find(l => l.startsWith("data:")); if (!line) continue;
        let ev; try { ev = JSON.parse(line.slice(5).trim()) } catch { continue }
        if (ev.k === "text") { acc += ev.text; body.innerHTML = md(acc) + '<span class="cursor"></span>' }
        else if (ev.k === "tool") {
          const s = document.createElement("span"); s.className = "tool";
          s.innerHTML = "<b>" + esc(ev.name) + "</b><span>" + esc(ev.input || "") + "</span>";
          toolbox.appendChild(s);
        }
        else if (ev.k === "error") {
          const d = document.createElement("div"); d.className = "err"; d.textContent = ev.text; wrap.appendChild(d);
        }
        else if (ev.k === "done") {
          body.innerHTML = acc ? md(acc) : '<span style="color:var(--muted)">(keine Textantwort)</span>';
          wrap.querySelector(".role").innerHTML = '<span class="tag">JP</span>' + new Date().toTimeString().slice(0, 5);
          if (ev.ms) {
            const mt = document.createElement("div"); mt.className = "meta";
            mt.textContent = (ev.ms / 1000).toFixed(1) + "s, " + (ev.turns || 1) + " Schritt(e)";
            wrap.appendChild(mt);
          }
        }
        box.scrollTop = box.scrollHeight;
      }
    }
    body.innerHTML = acc ? md(acc) : '<span style="color:var(--muted)">(keine Textantwort)</span>';
    cur = await api("/api/chat/" + cur.id); loadChats();
  } catch (e) {
    const d = document.createElement("div"); d.className = "err"; d.textContent = "Fehler: " + e.message;
    wrap.appendChild(d);
    const c = body.querySelector(".cursor"); if (c) c.remove();
  }
  busy = false; $("#send").style.display = ""; $("#stop").style.display = "none"; ta.focus();
}

/* ---------------- header actions ---------------- */
$("#new").onclick = async () => {
  try {
    const f = await api("/api/pick-folder", { method: "POST" });
    if (f.cancelled) return;
    cur = await api("/api/chats", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ cwd: f.path, model: $("#model").value, permission: $("#perm").value })
    });
    render(); loadChats(); ta.focus(); toast("Chat angelegt: " + base(f.path));
  } catch (e) { toast(e.message, true) }
};
$("#folder").onclick = async () => {
  if (!cur) return toast("Erst einen Chat oeffnen", true);
  const f = await api("/api/pick-folder", { method: "POST" });
  if (f.cancelled) return;
  await api("/api/chat/" + cur.id + "/update", {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ cwd: f.path })
  });
  cur.cwd = f.path; render(); loadChats(); toast("Ordner gewechselt");
};
$("#export").onclick = async () => {
  if (!cur) return toast("Erst einen Chat oeffnen", true);
  const r = await fetch("/api/chat/" + cur.id + "/export");
  const txt = await r.text();
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([txt], { type: "text/markdown" }));
  a.download = (cur.title || "chat").replace(/[^\w\-]+/g, "_").slice(0, 40) + ".md";
  document.body.appendChild(a); a.click(); a.remove();
  toast("Exportiert");
};
$("#model").onchange = async e => {
  const m = e.target.value;
  await api("/api/model", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ model: m }) });
  if (cur) {
    await api("/api/chat/" + cur.id + "/update", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ model: m }) });
    cur.model = m;
  }
  toast("Modell: " + short(m));
};
$("#perm").onchange = async e => {
  const p = e.target.value;
  await api("/api/permission", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ permission: p }) });
  if (cur) {
    await api("/api/chat/" + cur.id + "/update", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ permission: p }) });
    cur.permission = p;
  }
};
$("#test").onclick = async () => {
  const m = $("#model").value, b = $("#test");
  b.textContent = "..."; b.disabled = true;
  try {
    const r = await api("/api/model/test", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ model: m }) });
    if (r.ok) toast("antwortet: " + r.detail);
    else {
      toast("faellt aus: " + r.detail + " - suche Ersatz", true);
      const rp = await api("/api/repair", { method: "POST" });
      if (rp.changed) {
        await loadModels(); $("#model").value = rp.model;
        if (cur) { await api("/api/chat/" + cur.id + "/update", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ model: rp.model }) }); cur.model = rp.model }
        toast("gewechselt auf " + short(rp.model));
      } else if (rp.broken) toast("Kein Modell erreichbar - Schluessel oder Limit pruefen", true);
    }
  } catch (e) { toast(e.message, true) }
  b.textContent = "TEST"; b.disabled = false;
};

/* ---------------- modals ---------------- */
const open = id => $("#" + id).classList.add("on");
const close = id => $("#" + id).classList.remove("on");
$$("[data-close]").forEach(b => b.onclick = () => close(b.dataset.close));
$$(".overlay").forEach(o => o.onclick = e => { if (e.target === o && o.id !== "ovSetup") o.classList.remove("on") });
$$(".tab").forEach(t => t.onclick = () => {
  $$(".tab").forEach(x => x.classList.remove("on")); t.classList.add("on");
  $$(".tabpane").forEach(p => p.classList.remove("on")); $("#" + t.dataset.tab).classList.add("on");
});
document.addEventListener("keydown", e => {
  if (e.key === "Escape") $$(".overlay.on").forEach(o => { if (o.id !== "ovSetup") o.classList.remove("on") });
});

function checkHTML(s) {
  const rows = [
    ["Claude Code CLI", s.claude, s.claude_version || "nicht gefunden"],
    ["uv (Paketmanager)", s.uv, s.uv ? "installiert" : "fehlt"],
    ["Proxy installiert", s.fcc, s.fcc ? "installiert" : "fehlt"],
    ["Konfiguration", s.env, s.env ? "~/.fcc/.env" : "fehlt"],
    ["NVIDIA-Schluessel", s.key, s.key_masked || "nicht gesetzt"],
    ["Autostart", s.agent, s.agent ? "aktiv" : "fehlt"],
    ["Proxy laeuft", s.proxy, s.proxy ? "online" : "offline"],
  ];
  return rows.map(([n, ok, d]) =>
    '<div class="check"><span class="b ' + (ok ? "ok" : "no") + '">' + (ok ? "✓" : "✗") +
    '</span><span>' + n + '</span><span class="d">' + esc(d) + "</span></div>").join("");
}

$("#openSettings").onclick = async () => {
  open("ovSettings");
  try {
    const st = await api("/api/settings");
    $("#iData").textContent = st.data_dir;
    $("#iPort").textContent = st.port;
    const box = $("#keys"); box.innerHTML = "";
    st.providers.forEach(p => {
      const d = document.createElement("div"); d.className = "keyrow";
      d.innerHTML = '<div class="kh"><b>' + esc(p.label) + (p.required ? " (erforderlich)" : "") +
        '</b><span class="st ' + (p.set ? "ok" : "") + '">' + (p.set ? esc(p.masked) : "nicht gesetzt") + "</span></div>" +
        '<div class="kr"><input class="inp" type="password" placeholder="Schluessel einfuegen ..."><button class="btn">Speichern</button></div>' +
        '<div class="note" style="margin:7px 0 0"><a href="' + p.url + '" target="_blank">Schluessel holen</a></div>';
      const inp = d.querySelector("input"), btn = d.querySelector("button");
      btn.onclick = async () => {
        if (!inp.value.trim()) return toast("Kein Wert eingegeben", true);
        btn.disabled = true; btn.textContent = "...";
        try {
          await api("/api/settings/key", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ key: p.key, value: inp.value.trim() }) });
          inp.value = ""; toast(p.label + " gespeichert, Proxy neu gestartet");
          $("#openSettings").onclick();
          refreshStatus();
        } catch (e) { toast(e.message, true) }
        btn.disabled = false; btn.textContent = "Speichern";
      };
      box.appendChild(d);
    });
    const s = await api("/api/setup");
    $("#setupList").innerHTML = checkHTML(s);
    $("#iClaude").textContent = s.claude_version || "nicht gefunden";
  } catch (e) { toast(e.message, true) }
};

$("#btnRestart").onclick = async () => {
  toast("Proxy startet neu ...");
  const r = await api("/api/proxy/restart", { method: "POST" });
  toast(r.ok ? "Proxy laeuft" : "Proxy nicht erreichbar", !r.ok);
  refreshStatus(); $("#openSettings").onclick();
};
$("#btnRepair").onclick = async () => {
  toast("Suche funktionierendes Modell ...");
  const r = await api("/api/repair", { method: "POST" });
  if (r.changed) { await loadModels(); toast("gewechselt auf " + short(r.model)) }
  else if (r.broken) toast("Kein Modell erreichbar", true);
  else toast("Modell ist in Ordnung");
};

async function runInstall(logEl, btn, onDone) {
  logEl.style.display = ""; logEl.textContent = "";
  btn.disabled = true;
  const res = await fetch("/api/setup/install", { method: "POST" });
  const rd = res.body.getReader(), dec = new TextDecoder(); let buf = "", ok = false;
  for (;;) {
    const { value, done } = await rd.read(); if (done) break;
    buf += dec.decode(value, { stream: true });
    const parts = buf.split("\n\n"); buf = parts.pop();
    for (const p of parts) {
      const l = p.split("\n").find(x => x.startsWith("data:")); if (!l) continue;
      let ev; try { ev = JSON.parse(l.slice(5).trim()) } catch { continue }
      if (ev.line === "__DONE__") ok = true;
      else if (ev.line === "__DONE_ERR__") ok = false;
      else { logEl.textContent += ev.line + "\n"; logEl.scrollTop = logEl.scrollHeight }
    }
  }
  btn.disabled = false;
  if (onDone) onDone(ok);
}
$("#btnInstall").onclick = () => runInstall($("#installLog"), $("#btnInstall"), ok => {
  toast(ok ? "Installation abgeschlossen" : "Installation mit Fehlern", !ok);
  refreshStatus(); $("#openSettings").onclick();
});

/* ---------------- skills ---------------- */
function renderSkills(filter) {
  const q = (filter || "").toLowerCase();
  const box = $("#skillList"); box.innerHTML = "";
  const list = skillsCache.filter(s => !q || s.name.toLowerCase().includes(q) || (s.description || "").toLowerCase().includes(q));
  if (!list.length) { box.innerHTML = '<div class="note">Keine Skills gefunden.</div>'; return }
  list.forEach(s => {
    const d = document.createElement("div"); d.className = "skill" + (s.enabled ? "" : " off");
    const info = document.createElement("div"); info.className = "info";
    const n = document.createElement("div"); n.className = "n"; n.textContent = s.name;
    const ds = document.createElement("div"); ds.className = "ds"; ds.textContent = s.description || "";
    info.append(n, ds);
    const sw = document.createElement("div"); sw.className = "sw" + (s.enabled ? " on" : "");
    sw.onclick = async () => {
      try {
        await api("/api/skills/toggle", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ name: s.name, enabled: !s.enabled }) });
        s.enabled = !s.enabled; renderSkills($("#skillSearch").value); refreshStatus();
      } catch (e) { toast(e.message, true) }
    };
    d.append(info, sw); box.appendChild(d);
  });
}
$("#openSkills").onclick = async () => {
  open("ovSkills");
  try { skillsCache = await api("/api/skills"); renderSkills($("#skillSearch").value) }
  catch (e) { toast(e.message, true) }
};
$("#skillSearch").addEventListener("input", e => renderSkills(e.target.value));
$("#btnImportSkill").onclick = async () => {
  try {
    const r = await api("/api/skills/import", { method: "POST" });
    if (r.cancelled) return;
    toast("Skill importiert: " + r.name);
    skillsCache = await api("/api/skills"); renderSkills(""); refreshStatus();
  } catch (e) { toast(e.message, true) }
};

/* ---------------- first run ---------------- */
$("#btnSetupGo").onclick = async () => {
  const k = $("#setupKey").value.trim();
  if (k) {
    try { await api("/api/settings/key", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ key: "NVIDIA_NIM_API_KEY", value: k }) }) }
    catch (e) { return toast(e.message, true) }
    $("#setupKey").value = "";
  }
  await runInstall($("#setupLog"), $("#btnSetupGo"), async ok => {
    const s = await api("/api/setup");
    $("#setupList2").innerHTML = checkHTML(s);
    if (s.proxy && s.key && s.claude) {
      close("ovSetup"); toast("Einrichtung fertig");
      await loadModels(); refreshStatus();
    } else {
      toast("Noch nicht vollstaendig - siehe Liste", true);
    }
  });
};

/* ---------------- boot ---------------- */
(async () => {
  const s = await refreshStatus();
  try {
    const setup = await api("/api/setup");
    if (!setup.key || !setup.claude || !setup.fcc) {
      $("#setupList2").innerHTML = checkHTML(setup);
      open("ovSetup");
    }
  } catch {}
  try { await loadModels() } catch {}
  await loadChats(); render();
  setInterval(refreshStatus, 15000);
})();
