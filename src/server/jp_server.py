#!/usr/bin/env python3
"""JP Coding - lokaler Backend-Server. Nur Python-Standardbibliothek."""
import json, os, re, shutil, socket, subprocess, sys, threading, time, uuid
import urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

RES  = Path(__file__).resolve().parent.parent           # .../Contents/Resources
UI   = RES/'server'/'ui'
BIN  = RES/'bin'
HOME = Path.home()
FCC  = HOME/'.fcc'
FCCENV = FCC/'.env'
LOCALBIN = HOME/'.local'/'bin'
AGENT = HOME/'Library'/'LaunchAgents'/'com.freeclaudecode.server.plist'

def _data_dir():
    """Daten im Paket, solange beschreibbar - sonst Application Support."""
    cand = RES/'JPData'
    try:
        cand.mkdir(parents=True, exist_ok=True)
        p = cand/'.wtest'; p.write_text("x"); p.unlink()
        return cand
    except Exception:
        alt = HOME/'Library'/'Application Support'/'JP Coding'
        alt.mkdir(parents=True, exist_ok=True)
        return alt

DATA    = _data_dir()
CHATS   = DATA/'chats';           CHATS.mkdir(parents=True, exist_ok=True)
CFGDIR  = DATA/'claude-config';   CFGDIR.mkdir(parents=True, exist_ok=True)
SKILLS  = CFGDIR/'skills';        SKILLS.mkdir(parents=True, exist_ok=True)
SKOFF   = CFGDIR/'skills-disabled'; SKOFF.mkdir(parents=True, exist_ok=True)
RUNTIME = DATA/'runtime';         RUNTIME.mkdir(parents=True, exist_ok=True)
STATE   = DATA/'state.json'
PROFILE = RUNTIME/'isolate.sb'

PROVIDERS = [
    ("NVIDIA_NIM_API_KEY", "NVIDIA NIM", "https://build.nvidia.com/settings/api-keys", True),
    ("OPENROUTER_API_KEY", "OpenRouter", "https://openrouter.ai/keys", False),
    ("GROQ_API_KEY",       "Groq",       "https://console.groq.com/keys", False),
    ("CEREBRAS_API_KEY",   "Cerebras",   "https://cloud.cerebras.ai", False),
    ("GEMINI_API_KEY",     "Google Gemini", "https://aistudio.google.com/apikey", False),
    ("DEEPSEEK_API_KEY",   "DeepSeek",   "https://platform.deepseek.com/api_keys", False),
    ("MISTRAL_API_KEY",    "Mistral",    "https://console.mistral.ai/", False),
]

MIN_ENV = """NVIDIA_NIM_API_KEY=
MODEL=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
MODEL_OPUS=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
MODEL_SONNET=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
MODEL_HAIKU=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
ENABLE_MODEL_THINKING=true
ANTHROPIC_AUTH_TOKEN=jpcode
HOST=127.0.0.1
PORT=8082
PROVIDER_RATE_LIMIT=10
PROVIDER_MAX_CONCURRENCY=5
HTTP_READ_TIMEOUT=300
HTTP_CONNECT_TIMEOUT=60
"""

# ------------------------------------------------------------------ env
_lock = threading.Lock()

def env_text():
    try: return FCCENV.read_text()
    except Exception: return ""

def env_val(key, default=""):
    m = re.search(rf'^{re.escape(key)}=(.*)$', env_text(), re.M)
    return m.group(1).strip().strip('"\'') if m else default

def env_set(pairs):
    FCC.mkdir(parents=True, exist_ok=True)
    if not FCCENV.exists():
        tpl = None
        for p in LOCALBIN.parent.glob('share/uv/tools/free-claude-code/lib/*/site-packages/cli/env.example'):
            tpl = p; break
        FCCENV.write_text(tpl.read_text() if tpl else MIN_ENV)
    txt = FCCENV.read_text()
    for k, v in pairs.items():
        if re.search(rf'^{re.escape(k)}=', txt, re.M):
            txt = re.sub(rf'^{re.escape(k)}=.*$', f'{k}={v}', txt, flags=re.M)
        else:
            txt = txt.rstrip("\n") + f"\n{k}={v}\n"
    with _lock: FCCENV.write_text(txt)

def merge_env_template():
    """Fehlende Werte aus der Original-Vorlage ergaenzen, vorhandene nie ueberschreiben."""
    tpl = None
    for q in (LOCALBIN.parent/'share'/'uv'/'tools'/'free-claude-code'/'lib').glob('*/site-packages/cli/env.example'):
        tpl = q; break
    if not tpl or not FCCENV.exists(): return 0
    have = {m.group(1) for m in re.finditer(r'^([A-Z0-9_]+)=', FCCENV.read_text(), re.M)}
    add = []
    for line in tpl.read_text().splitlines():
        m = re.match(r'^([A-Z0-9_]+)=', line)
        if m and m.group(1) not in have:
            add.append(line)
    if add:
        with _lock:
            FCCENV.write_text(FCCENV.read_text().rstrip("\n") + "\n" + "\n".join(add) + "\n")
    return len(add)

def proxy_port(): return env_val("PORT", "8082") or "8082"
def PROXY(): return f"http://127.0.0.1:{proxy_port()}"
def auth_token(): return env_val("ANTHROPIC_AUTH_TOKEN", "jpcode") or "jpcode"

# ------------------------------------------------------------------ state
def load_state():
    if STATE.exists():
        try: return json.loads(STATE.read_text())
        except Exception: pass
    try: first = json.loads((BIN/'models.json').read_text())[0]
    except Exception: first = "anthropic/nvidia_nim/nvidia/nemotron-3-super-120b-a12b"
    return {"model": first, "permission": "bypassPermissions", "last_dir": str(HOME/'Downloads')}

def save_state(s):
    with _lock: STATE.write_text(json.dumps(s, indent=2))

# ------------------------------------------------------------------ sandbox
def write_profile():
    app = str(RES.parent.parent)
    p = f'''(version 1)
(allow default)
(deny file-write*
    (subpath "{HOME}/.claude")
    (subpath "{HOME}/Library/Application Support/Claude")
    (subpath "{FCC}")
    (subpath "{HOME}/Library/LaunchAgents")
    (literal "{HOME}/.zshrc") (literal "{HOME}/.zprofile") (literal "{HOME}/.zshenv")
    (literal "{HOME}/.bash_profile") (literal "{HOME}/.profile"))
(deny file-write* (subpath "{app}"))
(allow file-write* (subpath "{CFGDIR}"))
(deny file-write*
    (subpath "{SKILLS}")
    (subpath "{SKOFF}")
    (subpath "{CHATS}")
    (subpath "{RUNTIME}"))
(deny file-read*
    (literal "{FCCENV}")
    (subpath "{HOME}/.ssh")
    (subpath "{HOME}/.aws"))
'''
    PROFILE.write_text(p)
    return PROFILE

# ------------------------------------------------------------------ proxy
def proxy_up(t=1.5):
    try:
        urllib.request.urlopen(f"{PROXY()}/health", timeout=t); return True
    except Exception: return False

def agent_loaded():
    r = subprocess.run(["launchctl", "print", f"gui/{os.getuid()}/com.freeclaudecode.server"],
                       capture_output=True)
    return r.returncode == 0

def ensure_proxy(wait=30):
    if proxy_up(): return True
    if AGENT.exists():
        if not agent_loaded():
            subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(AGENT)],
                           capture_output=True)
        subprocess.run(["launchctl", "kickstart", f"gui/{os.getuid()}/com.freeclaudecode.server"],
                       capture_output=True)
    elif (LOCALBIN/'fcc-server').exists():
        subprocess.Popen([str(LOCALBIN/'fcc-server')],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         env={**os.environ, "FCC_OPEN_BROWSER": "false"})
    for _ in range(int(wait/0.5)):
        if proxy_up(): return True
        time.sleep(0.5)
    return False

def restart_proxy():
    if AGENT.exists():
        subprocess.run(["launchctl", "kickstart", "-k", f"gui/{os.getuid()}/com.freeclaudecode.server"],
                       capture_output=True)
    else:
        subprocess.run(["pkill", "-f", "fcc-server"], capture_output=True)
    time.sleep(1.0)
    return ensure_proxy(25)

def all_models():
    try:
        req = urllib.request.Request(f"{PROXY()}/v1/models",
              headers={"x-api-key": auth_token(), "anthropic-version": "2023-06-01"})
        with urllib.request.urlopen(req, timeout=8) as r:
            return [m.get("id") for m in json.loads(r.read()).get("data", []) if m.get("id")]
    except Exception:
        return []

BADTXT = ("Provider API request failed", "Invalid request sent to provider",
          "Provider returned an error")

def test_model(model, timeout=50):
    body = json.dumps({"model": model, "max_tokens": 16,
        "messages": [{"role": "user", "content": "Reply with exactly: OK"}]}).encode()
    req = urllib.request.Request(f"{PROXY()}/v1/messages", data=body,
        headers={"content-type": "application/json", "x-api-key": auth_token(),
                 "anthropic-version": "2023-06-01"})
    txt = ""
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            for raw in r:
                l = raw.decode("utf8", "replace").strip()
                if not l.startswith("data:"): continue
                try: ev = json.loads(l[5:].strip())
                except Exception: continue
                if ev.get("type") == "content_block_delta":
                    d = ev.get("delta", {})
                    if d.get("type") == "text_delta": txt += d.get("text", "")
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}"
    except Exception as e:
        return False, str(e)[:80]
    if not txt.strip(): return False, "leere Antwort"
    if any(b in txt for b in BADTXT): return False, txt.strip()[:80]
    return True, txt.strip()[:40]

def ensure_model():
    st = load_state(); cur = st.get("model", "")
    ok, _ = test_model(cur)
    if ok: return {"changed": False, "model": cur}
    try: cands = json.loads((BIN/'models.json').read_text())
    except Exception: cands = []
    for m in [x for x in cands if x != cur]:
        ok, _ = test_model(m)
        if ok:
            st["model"] = m; save_state(st)
            return {"changed": True, "model": m, "old": cur}
    return {"changed": False, "model": cur, "broken": True}

# ------------------------------------------------------------------ setup
def claude_bin():
    return shutil.which("claude") or next(
        (p for p in ("/opt/homebrew/bin/claude", "/usr/local/bin/claude") if os.path.exists(p)), None)

def setup_state():
    cb = claude_bin()
    ver = ""
    if cb:
        try: ver = subprocess.run([cb, "--version"], capture_output=True, text=True, timeout=15).stdout.strip()
        except Exception: ver = "?"
    key = env_val("NVIDIA_NIM_API_KEY")
    return {
        "claude": bool(cb), "claude_version": ver, "claude_path": cb or "",
        "uv": bool(shutil.which("uv") or (LOCALBIN/'uv').exists()),
        "fcc": (LOCALBIN/'fcc-server').exists(),
        "env": FCCENV.exists(),
        "key": bool(key), "key_masked": (key[:6] + "..." + key[-4:]) if len(key) > 12 else ("gesetzt" if key else ""),
        "agent": AGENT.exists(),
        "proxy": proxy_up(),
        "data_dir": str(DATA),
        "in_bundle": str(DATA).startswith(str(RES)),
    }

def sh(cmd, log, env=None, timeout=900):
    log(f"$ {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    try:
        p = subprocess.Popen(cmd, shell=isinstance(cmd, str), stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, bufsize=1,
                             env={**os.environ, **(env or {})})
        for line in p.stdout:
            log(line.rstrip())
        p.wait(timeout=timeout)
        return p.returncode == 0
    except Exception as e:
        log(f"FEHLER: {e}"); return False

def install_all(log):
    ok = True
    env = {"PATH": f"{LOCALBIN}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"}
    if not claude_bin():
        log("== Claude Code CLI installieren ==")
        if shutil.which("npm"):
            ok &= sh(["npm", "install", "-g", "@anthropic-ai/claude-code"], log, env)
        else:
            log("npm fehlt. Bitte Node.js installieren: https://nodejs.org")
            ok = False
    else:
        log("Claude Code CLI: bereits vorhanden")

    if not (shutil.which("uv") or (LOCALBIN/'uv').exists()):
        log("== uv installieren ==")
        ok &= sh("curl -LsSf https://astral.sh/uv/install.sh | sh", log, env)
    else:
        log("uv: bereits vorhanden")

    if not (LOCALBIN/'fcc-server').exists():
        log("== Proxy (free-claude-code) installieren ==")
        uvb = str(LOCALBIN/'uv') if (LOCALBIN/'uv').exists() else "uv"
        ok &= sh([uvb, "tool", "install",
                  "git+https://github.com/Alishahryar1/free-claude-code.git"], log, env)
    else:
        log("Proxy: bereits vorhanden")

    if not FCCENV.exists():
        log("== Konfiguration anlegen ==")
        env_set({})
        log(f"angelegt: {FCCENV}")
    n = merge_env_template()
    if n: log(f"== Konfiguration ergaenzt: {n} fehlende Werte aus der Vorlage ==")

    env_set({"HOST": "127.0.0.1"})

    if not AGENT.exists():
        log("== Autostart einrichten ==")
        AGENT.parent.mkdir(parents=True, exist_ok=True)
        AGENT.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.freeclaudecode.server</string>
  <key>ProgramArguments</key><array><string>{LOCALBIN}/fcc-server</string></array>
  <key>EnvironmentVariables</key><dict>
    <key>FCC_OPEN_BROWSER</key><string>false</string>
    <key>PATH</key><string>{LOCALBIN}:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>WorkingDirectory</key><string>{HOME}</string>
  <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>{FCC}/logs/launchd.out.log</string>
  <key>StandardErrorPath</key><string>{FCC}/logs/launchd.err.log</string>
</dict></plist>''')
        (FCC/'logs').mkdir(parents=True, exist_ok=True)
        subprocess.run(["launchctl", "bootstrap", f"gui/{os.getuid()}", str(AGENT)], capture_output=True)
        log("Autostart aktiv")

    log("== Proxy starten ==")
    log("Proxy erreichbar" if ensure_proxy(45) else "Proxy nicht erreichbar - Log: ~/.fcc/logs/server.log")
    log("FERTIG" if ok else "MIT FEHLERN BEENDET")
    return ok

# ------------------------------------------------------------------ skills
def skill_desc(d):
    f = d/'SKILL.md'
    if not f.exists(): return ""
    try: t = f.read_text(errors="replace")[:2500]
    except Exception: return ""
    m = re.search(r'^description:\s*(.+)$', t, re.M)
    if m: return m.group(1).strip().strip('"\'')[:200]
    m = re.search(r'^#\s+(.+)$', t, re.M)
    return m.group(1).strip()[:200] if m else ""

def list_skills():
    out = []
    for base, on in ((SKILLS, True), (SKOFF, False)):
        for d in sorted(base.glob("*")):
            if d.is_dir() and not d.name.startswith("."):
                out.append({"name": d.name, "enabled": on, "description": skill_desc(d)})
    return sorted(out, key=lambda x: x["name"].lower())

# ------------------------------------------------------------------ chats
def chat_path(cid): return CHATS/f"{cid}.json"
def load_chat(cid):
    p = chat_path(cid)
    if not p.exists(): return None
    try: return json.loads(p.read_text())
    except Exception: return None
def save_chat(c):
    with _lock: chat_path(c["id"]).write_text(json.dumps(c, indent=2))
def list_chats():
    out = []
    for p in CHATS.glob("*.json"):
        try:
            c = json.loads(p.read_text())
            out.append({k: c.get(k) for k in ("id", "title", "cwd", "model", "updated", "created")})
        except Exception: pass
    return sorted(out, key=lambda x: x.get("updated") or "", reverse=True)

RUNNING = {}

def claude_env():
    e = {k: v for k, v in os.environ.items() if not k.startswith("ANTHROPIC_")}
    e["ANTHROPIC_BASE_URL"] = PROXY()
    e["ANTHROPIC_AUTH_TOKEN"] = auth_token()
    e["CLAUDE_CONFIG_DIR"] = str(CFGDIR)
    e["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
    e["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = "190000"
    return e

def run_claude(chat, prompt):
    cb = claude_bin()
    if not cb:
        yield {"type": "fatal", "error": "Claude Code CLI nicht gefunden. Einstellungen > Setup."}
        return
    write_profile()
    cmd = ["/usr/bin/sandbox-exec", "-f", str(PROFILE), cb,
           "-p", "--output-format", "stream-json", "--verbose",
           "--model", chat["model"],
           "--permission-mode", chat.get("permission", "bypassPermissions")]
    if chat.get("session_id"): cmd += ["--resume", chat["session_id"]]
    cwd = chat["cwd"] if os.path.isdir(chat["cwd"]) else str(HOME/'Downloads')
    p = subprocess.Popen(cmd, cwd=cwd, env=claude_env(), stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    RUNNING[chat["id"]] = p
    try:
        p.stdin.write(prompt); p.stdin.close()
    except Exception: pass
    try:
        for line in p.stdout:
            line = line.strip()
            if not line: continue
            try: yield json.loads(line)
            except Exception: pass
        err = (p.stderr.read() or "").strip()
        p.wait()
        if p.returncode not in (0,) and err:
            yield {"type": "fatal", "error": err[:800]}
    finally:
        RUNNING.pop(chat["id"], None)

def _short(v, n=170):
    try: s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
    except Exception: s = str(v)
    return s[:n] + ("..." if len(s) > n else "")

def export_md(c):
    L = [f"# {c.get('title','Chat')}", "", f"Ordner: `{c.get('cwd','')}`",
         f"Modell: `{c.get('model','')}`", f"Erstellt: {c.get('created','')}", "", "---", ""]
    for m in c.get("messages", []):
        L.append(f"### {'Du' if m['role']=='user' else 'JP Coding'}  ·  {m.get('ts','')}")
        L.append("")
        L.append(m.get("text") or "")
        if m.get("tools"): L.append("")
        if m.get("tools"): L.append("_Tools: " + ", ".join(m["tools"]) + "_")
        L.append("")
    return "\n".join(L)

# ------------------------------------------------------------------ http
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass

    def _send(self, code, body=b"", ctype="application/json"):
        if isinstance(body, str): body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            try: self.wfile.write(body)
            except Exception: pass

    def _json(self, o, code=200): self._send(code, json.dumps(o).encode())
    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        try: return json.loads(self.rfile.read(n) or b"{}")
        except Exception: return {}

    def _file(self, p, ctype):
        try: self._send(200, p.read_bytes(), ctype)
        except Exception: self._send(404, b"not found", "text/plain")

    def do_GET(self):
        path = self.path.split("?")[0]
        if path in ("/", "/index.html"): return self._file(UI/'index.html', "text/html; charset=utf-8")
        if path == "/app.js":    return self._file(UI/'app.js', "application/javascript; charset=utf-8")
        if path == "/style.css": return self._file(UI/'style.css', "text/css; charset=utf-8")
        try:
            if path == "/api/status":
                st = load_state()
                return self._json({"proxy": proxy_up(), "model": st["model"],
                    "permission": st.get("permission", "bypassPermissions"),
                    "skills": sum(1 for d in SKILLS.glob("*") if d.is_dir() and not d.name.startswith(".")), "data_dir": str(DATA),
                    "claude": bool(claude_bin()), "key": bool(env_val("NVIDIA_NIM_API_KEY"))})
            if path == "/api/setup":   return self._json(setup_state())
            if path == "/api/settings":
                st = load_state()
                keys = []
                for k, label, url, req in PROVIDERS:
                    v = env_val(k)
                    keys.append({"key": k, "label": label, "url": url, "required": req,
                                 "set": bool(v),
                                 "masked": (v[:6] + "..." + v[-4:]) if len(v) > 12 else ("gesetzt" if v else "")})
                return self._json({"providers": keys, "model": st["model"],
                    "permission": st.get("permission", "bypassPermissions"),
                    "port": proxy_port(), "data_dir": str(DATA)})
            if path == "/api/models":
                try: cur8 = json.loads((BIN/'models.json').read_text())
                except Exception: cur8 = []
                return self._json({"curated": cur8, "all": all_models(), "current": load_state()["model"]})
            if path == "/api/skills": return self._json(list_skills())
            if path == "/api/chats":  return self._json(list_chats())
            if path.startswith("/api/chat/") and path.endswith("/export"):
                c = load_chat(path.split("/")[3])
                if not c: return self._json({"error": "nicht gefunden"}, 404)
                return self._send(200, export_md(c).encode(), "text/markdown; charset=utf-8")
            if path.startswith("/api/chat/"):
                c = load_chat(path.split("/")[-1])
                return self._json(c) if c else self._json({"error": "nicht gefunden"}, 404)
        except Exception as e:
            return self._json({"error": str(e)[:300]}, 500)
        return self._send(404, b'{"error":"404"}')

    def do_POST(self):
        path = self.path.split("?")[0]
        try:
            if path == "/api/pick-folder":  return self.pick(folder=True)
            if path == "/api/pick-files":   return self.pick(folder=False)

            if path == "/api/settings/key":
                b = self._body(); k = b.get("key"); v = (b.get("value") or "").strip()
                if k not in [p[0] for p in PROVIDERS]: return self._json({"error": "unbekannt"}, 400)
                env_set({k: v})
                changed = restart_proxy()
                return self._json({"ok": True, "proxy": changed})

            if path == "/api/proxy/restart":
                return self._json({"ok": restart_proxy()})

            if path == "/api/setup/install":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream; charset=utf-8")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Connection", "close")
                self.end_headers(); self.close_connection = True
                def log(m):
                    try:
                        self.wfile.write(f"data: {json.dumps({'line': m})}\n\n".encode()); self.wfile.flush()
                    except Exception: raise BrokenPipeError
                try:
                    ok = install_all(log)
                    log("__DONE__" if ok else "__DONE_ERR__")
                except BrokenPipeError: pass
                except Exception as e:
                    try: log("FEHLER: " + str(e)[:200]); log("__DONE_ERR__")
                    except Exception: pass
                return

            if path == "/api/model":
                b = self._body(); st = load_state(); st["model"] = b["model"]; save_state(st)
                return self._json({"ok": True, "model": b["model"]})
            if path == "/api/permission":
                b = self._body(); st = load_state(); st["permission"] = b["permission"]; save_state(st)
                return self._json({"ok": True})
            if path == "/api/model/test":
                ok, msg = test_model(self._body().get("model", ""))
                return self._json({"ok": ok, "detail": msg})
            if path == "/api/repair":
                return self._json(ensure_model())

            if path == "/api/skills/toggle":
                b = self._body(); name = b.get("name", ""); on = bool(b.get("enabled"))
                if "/" in name or ".." in name: return self._json({"error": "ungueltig"}, 400)
                src, dst = (SKOFF/name, SKILLS/name) if on else (SKILLS/name, SKOFF/name)
                if not src.exists(): return self._json({"error": "nicht gefunden"}, 404)
                if dst.exists(): shutil.rmtree(dst, ignore_errors=True)
                shutil.move(str(src), str(dst))
                return self._json({"ok": True})

            if path == "/api/skills/import":
                r = self.osa('choose folder with prompt "Skill-Ordner waehlen (mit SKILL.md)"')
                if not r: return self._json({"cancelled": True})
                src = Path(r)
                if not (src/'SKILL.md').exists():
                    return self._json({"error": "Kein SKILL.md in diesem Ordner"}, 400)
                dst = SKILLS/src.name
                if dst.exists(): shutil.rmtree(dst, ignore_errors=True)
                shutil.copytree(src, dst)
                return self._json({"ok": True, "name": src.name})

            if path == "/api/chats":
                b = self._body(); st = load_state()
                now = time.strftime("%Y-%m-%d %H:%M")
                c = {"id": uuid.uuid4().hex[:12], "title": b.get("title") or "Neuer Chat",
                     "cwd": b.get("cwd") or str(HOME/'Downloads'),
                     "model": b.get("model") or st["model"],
                     "permission": b.get("permission") or st.get("permission", "bypassPermissions"),
                     "created": now, "updated": now, "session_id": None, "messages": []}
                save_chat(c); return self._json(c)

            if path.startswith("/api/chat/"):
                parts = path.split("/"); cid = parts[3]; act = parts[4] if len(parts) > 4 else ""
                if act == "delete":
                    p = chat_path(cid)
                    if p.exists(): p.unlink()
                    return self._json({"ok": True})
                if act == "stop":
                    pr = RUNNING.get(cid)
                    if pr:
                        try: pr.terminate()
                        except Exception: pass
                    return self._json({"ok": bool(pr)})
                if act == "update":
                    c = load_chat(cid)
                    if not c: return self._json({"error": "nicht gefunden"}, 404)
                    b = self._body()
                    for k in ("model", "permission", "cwd", "title"):
                        if b.get(k): c[k] = b[k]
                    save_chat(c); return self._json(c)
                if act == "send":
                    return self.stream_send(cid)
            return self._send(404, b'{"error":"404"}')
        except Exception as e:
            return self._json({"error": str(e)[:300]}, 500)

    def osa(self, script):
        st = load_state()
        d = st.get("last_dir") or str(HOME/'Downloads')
        if not os.path.isdir(d): d = str(HOME/'Downloads')
        full = f'try\n set f to {script} default location POSIX file "{d}"\n'
        if "choose file" in script:
            full += ' set out to ""\n repeat with i in f\n set out to out & POSIX path of i & linefeed\n end repeat\n return out\n'
        else:
            full += ' return POSIX path of f\n'
        full += "end try"
        r = subprocess.run(["osascript", "-e", full], capture_output=True, text=True)
        return r.stdout.strip()

    def pick(self, folder):
        if folder:
            sel = self.osa('choose folder with prompt "Ordner fuer diesen Chat"')
            sel = sel.rstrip("/")
            if not sel: return self._json({"cancelled": True})
            if sel == str(HOME):
                return self._json({"error": "Home-Verzeichnis nicht erlaubt. Bitte Unterordner waehlen."}, 400)
            st = load_state(); st["last_dir"] = sel; save_state(st)
            return self._json({"path": sel})
        out = self.osa('choose file with prompt "Dateien anhaengen" with multiple selections allowed')
        files = [l.strip() for l in out.splitlines() if l.strip()]
        if not files: return self._json({"cancelled": True})
        return self._json({"files": files})

    def stream_send(self, cid):
        b = self._body()
        prompt = (b.get("text") or "").strip()
        files = b.get("files") or []
        c = load_chat(cid)
        if not c: return self._json({"error": "Chat nicht gefunden"}, 404)
        if not prompt and not files: return self._json({"error": "leer"}, 400)
        if b.get("model"): c["model"] = b["model"]
        if b.get("permission"): c["permission"] = b["permission"]
        if not ensure_proxy(20): return self._json({"error": "Proxy nicht erreichbar"}, 503)

        full = prompt
        if files:
            full = ("Angehaengte Dateien (lies sie bei Bedarf mit dem Read-Tool):\n"
                    + "\n".join("- " + f for f in files) + "\n\n" + prompt)

        c["messages"].append({"role": "user", "text": prompt, "files": files,
                              "ts": time.strftime("%H:%M")})
        if c["title"] == "Neuer Chat":
            c["title"] = (prompt or (files and Path(files[0]).name) or "Chat")[:46]
        save_chat(c)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        self.close_connection = True

        def push(o):
            try:
                self.wfile.write(f"data: {json.dumps(o)}\n\n".encode()); self.wfile.flush()
            except Exception: raise BrokenPipeError

        assistant = ""; tools = []
        try:
            for ev in run_claude(c, full):
                t = ev.get("type")
                if t == "system" and ev.get("subtype") == "init":
                    if ev.get("session_id"): c["session_id"] = ev["session_id"]
                    push({"k": "init", "model": ev.get("model"), "tools": len(ev.get("tools") or [])})
                elif t == "assistant":
                    for blk in (ev.get("message", {}).get("content") or []):
                        if blk.get("type") == "text" and blk.get("text"):
                            assistant += blk["text"]; push({"k": "text", "text": blk["text"]})
                        elif blk.get("type") == "tool_use":
                            tools.append(blk.get("name", "tool"))
                            push({"k": "tool", "name": blk.get("name", "tool"),
                                  "input": _short(blk.get("input"))})
                elif t == "user":
                    for blk in (ev.get("message", {}).get("content") or []):
                        if blk.get("type") == "tool_result":
                            push({"k": "tool_result", "text": _short(blk.get("content"), 300)})
                elif t == "result":
                    push({"k": "done", "ms": ev.get("duration_ms"),
                          "turns": ev.get("num_turns"), "error": ev.get("is_error")})
                elif t == "fatal":
                    push({"k": "error", "text": ev.get("error")})
        except BrokenPipeError:
            try:
                pr = RUNNING.get(cid)
                if pr: pr.terminate()
            except Exception: pass
        except Exception as e:
            try: push({"k": "error", "text": str(e)[:300]})
            except Exception: pass

        c["messages"].append({"role": "assistant", "text": assistant, "tools": tools,
                              "ts": time.strftime("%H:%M")})
        c["updated"] = time.strftime("%Y-%m-%d %H:%M")
        save_chat(c)
        try: push({"k": "saved"})
        except Exception: pass


def free_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); p = s.getsockname()[1]; s.close(); return p

def main():
    write_profile()
    threading.Thread(target=lambda: (ensure_proxy(40), ensure_model()), daemon=True).start()
    port = int(os.environ.get("JP_PORT") or free_port())
    (DATA/'port').write_text(str(port))
    srv = ThreadingHTTPServer(("127.0.0.1", port), H)
    srv.daemon_threads = True
    print(f"JP Coding backend  http://127.0.0.1:{port}  data={DATA}", flush=True)
    srv.serve_forever()

if __name__ == "__main__":
    main()
