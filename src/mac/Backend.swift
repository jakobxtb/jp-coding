import Foundation

enum Backend {

    // MARK: - .env

    static let providers: [ProviderKey] = [
        ProviderKey(key: "NVIDIA_NIM_API_KEY", label: "NVIDIA NIM",
                    url: "https://build.nvidia.com/settings/api-keys", required: true),
        ProviderKey(key: "OPENROUTER_API_KEY", label: "OpenRouter",
                    url: "https://openrouter.ai/keys", required: false),
        ProviderKey(key: "GROQ_API_KEY", label: "Groq",
                    url: "https://console.groq.com/keys", required: false),
        ProviderKey(key: "CEREBRAS_API_KEY", label: "Cerebras",
                    url: "https://cloud.cerebras.ai", required: false),
        ProviderKey(key: "GEMINI_API_KEY", label: "Google Gemini",
                    url: "https://aistudio.google.com/apikey", required: false),
        ProviderKey(key: "DEEPSEEK_API_KEY", label: "DeepSeek",
                    url: "https://platform.deepseek.com/api_keys", required: false),
        ProviderKey(key: "MISTRAL_API_KEY", label: "Mistral",
                    url: "https://console.mistral.ai/", required: false),
        ProviderKey(key: "ZAI_API_KEY", label: "Z.AI (GLM)",
                    url: "https://z.ai/manage-apikey/apikey-list", required: false),
        ProviderKey(key: "KIMI_API_KEY", label: "Moonshot (Kimi)",
                    url: "https://platform.moonshot.ai/console/api-keys", required: false),
        ProviderKey(key: "FIREWORKS_API_KEY", label: "Fireworks",
                    url: "https://fireworks.ai/account/api-keys", required: false),
    ]

    static let minEnv = """
    NVIDIA_NIM_API_KEY=
    MODEL=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
    MODEL_OPUS=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
    MODEL_SONNET=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
    MODEL_HAIKU=nvidia_nim/nvidia/nemotron-3-super-120b-a12b
    ENABLE_MODEL_THINKING=true
    FAST_PREFIX_DETECTION=true
    ANTHROPIC_AUTH_TOKEN=jpcode
    HOST=127.0.0.1
    PORT=8082
    PROVIDER_RATE_LIMIT=10
    PROVIDER_MAX_CONCURRENCY=5
    HTTP_READ_TIMEOUT=300
    HTTP_CONNECT_TIMEOUT=60

    """

    static func envText() -> String {
        (try? String(contentsOf: Paths.fccEnv, encoding: .utf8)) ?? ""
    }

    static func envValue(_ key: String) -> String {
        for line in envText().components(separatedBy: .newlines) {
            if line.hasPrefix(key + "=") {
                return String(line.dropFirst(key.count + 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        return ""
    }

    @discardableResult
    static func envSet(_ pairs: [String: String]) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.fccEnv.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: Paths.fccEnv.path) {
            var tpl = minEnv
            if let t = packageEnvTemplate() { tpl = t }
            try? tpl.write(to: Paths.fccEnv, atomically: true, encoding: .utf8)
        }
        var lines = envText().components(separatedBy: .newlines)
        for (k, v) in pairs {
            var found = false
            for i in lines.indices where lines[i].hasPrefix(k + "=") {
                lines[i] = "\(k)=\(v)"; found = true
            }
            if !found { lines.append("\(k)=\(v)") }
        }
        let out = lines.joined(separator: "\n")
        return (try? out.write(to: Paths.fccEnv, atomically: true, encoding: .utf8)) != nil
    }

    static func packageEnvTemplate() -> String? {
        let base = Paths.home.appendingPathComponent(".local/share/uv/tools/free-claude-code/lib")
        guard let dirs = try? FileManager.default.contentsOfDirectory(at: base,
                includingPropertiesForKeys: nil) else { return nil }
        for d in dirs {
            let p = d.appendingPathComponent("site-packages/cli/env.example")
            if let s = try? String(contentsOf: p, encoding: .utf8) { return s }
        }
        return nil
    }

    /// Fehlende Werte aus der Originalvorlage ergaenzen, vorhandene nie ueberschreiben.
    @discardableResult
    static func mergeEnvTemplate() -> Int {
        guard let tpl = packageEnvTemplate(),
              FileManager.default.fileExists(atPath: Paths.fccEnv.path) else { return 0 }
        let have = Set(envText().components(separatedBy: .newlines).compactMap { line -> String? in
            guard let i = line.firstIndex(of: "="), !line.hasPrefix("#") else { return nil }
            return String(line[line.startIndex..<i])
        })
        var add: [String] = []
        for line in tpl.components(separatedBy: .newlines) {
            guard let i = line.firstIndex(of: "="), !line.hasPrefix("#") else { continue }
            let k = String(line[line.startIndex..<i])
            if !k.isEmpty && !have.contains(k) { add.append(line) }
        }
        if add.isEmpty { return 0 }
        let out = envText().trimmingCharacters(in: .newlines) + "\n" + add.joined(separator: "\n") + "\n"
        try? out.write(to: Paths.fccEnv, atomically: true, encoding: .utf8)
        return add.count
    }

    static var proxyPort: String {
        let p = envValue("PORT"); return p.isEmpty ? "8082" : p
    }
    static var proxyBase: String { "http://127.0.0.1:\(proxyPort)" }
    static var authToken: String {
        let t = envValue("ANTHROPIC_AUTH_TOKEN"); return t.isEmpty ? "jpcode" : t
    }

    // MARK: - Shell

    @discardableResult
    static func run(_ launch: String, _ args: [String], timeout: TimeInterval = 60) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(Paths.localBin.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        do { try p.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    static func which(_ name: String) -> String? {
        for base in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                     Paths.localBin.path] {
            let p = base + "/" + name
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let (_, out) = run("/usr/bin/which", [name])
        let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static var claudeBin: String? { which("claude") }

    // MARK: - Proxy

    static func proxyUp(timeout: TimeInterval = 2) async -> Bool {
        guard let u = URL(string: proxyBase + "/health") else { return false }
        var r = URLRequest(url: u); r.timeoutInterval = timeout
        do { let (_, resp) = try await URLSession.shared.data(for: r)
             return (resp as? HTTPURLResponse)?.statusCode == 200 }
        catch { return false }
    }

    static var uid: String { String(getuid()) }

    static func ensureProxy(wait: TimeInterval = 30) async -> Bool {
        if await proxyUp() { return true }
        if FileManager.default.fileExists(atPath: Paths.launchAgent.path) {
            let (rc, _) = run("/bin/launchctl", ["print", "gui/\(uid)/com.freeclaudecode.server"])
            if rc != 0 {
                run("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.launchAgent.path])
            }
            run("/bin/launchctl", ["kickstart", "gui/\(uid)/com.freeclaudecode.server"])
        } else if FileManager.default.isExecutableFile(atPath: Paths.localBin.appendingPathComponent("fcc-server").path) {
            let p = Process()
            p.executableURL = Paths.localBin.appendingPathComponent("fcc-server")
            var env = ProcessInfo.processInfo.environment
            env["FCC_OPEN_BROWSER"] = "false"
            p.environment = env
            try? p.run()
        }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if await proxyUp() { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    static func restartProxy() async -> Bool {
        if FileManager.default.fileExists(atPath: Paths.launchAgent.path) {
            run("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/com.freeclaudecode.server"])
        } else {
            run("/usr/bin/pkill", ["-f", "fcc-server"])
        }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        return await ensureProxy(wait: 25)
    }

    static func allModels() async -> [String] {
        guard let u = URL(string: proxyBase + "/v1/models") else { return [] }
        var r = URLRequest(url: u); r.timeoutInterval = 10
        r.setValue(authToken, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let arr = j["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["id"] as? String }
    }

    static let badText = ["Provider API request failed", "Invalid request sent to provider",
                          "Provider returned an error"]

    /// Einzelabfrage gegen den Proxy; liefert (ok, Detail).
    static func testModel(_ model: String, timeout: TimeInterval = 130) async -> (Bool, String) {
        guard let u = URL(string: proxyBase + "/v1/messages") else { return (false, "URL") }
        var r = URLRequest(url: u); r.httpMethod = "POST"; r.timeoutInterval = timeout
        r.setValue("application/json", forHTTPHeaderField: "content-type")
        r.setValue(authToken, forHTTPHeaderField: "x-api-key")
        r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // 256 Token, nicht 16: Reasoning-Modelle wie gpt-oss verbrauchen das Budget
        // im Denkteil und liefern sonst gar keinen sichtbaren Text.
        let body: [String: Any] = ["model": model, "max_tokens": 256,
            "messages": [["role": "user", "content": "Reply with exactly: OK"]]]
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        var text = ""
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: r)
            if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
                return (false, "HTTP \(h.statusCode)")
            }
            for try await line in bytes.lines {
                guard line.hasPrefix("data:") else { continue }
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard let d = payload.data(using: .utf8),
                      let e = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
                else { continue }
                if e["type"] as? String == "content_block_delta",
                   let del = e["delta"] as? [String: Any],
                   del["type"] as? String == "text_delta",
                   let t = del["text"] as? String { text += t }
            }
        } catch { return (false, String("\(error)".prefix(70))) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return (false, "leere Antwort") }
        for b in badText where trimmed.contains(b) { return (false, String(trimmed.prefix(70))) }
        return (true, String(trimmed.prefix(40)))
    }

    /// Echter Test: startet Claude Code genau so wie der Chat es tut.
    /// Eine blosse API-Anfrage sagt nichts aus - Modelle scheitern erst am
    /// grossen System-Prompt mit allen Werkzeugdefinitionen.
    static func testModelViaAgent(_ model: String, timeout: TimeInterval = 120) async -> (Bool, String) {
        guard let claude = claudeBin else { return (false, "Claude Code CLI fehlt") }
        let profile = writeProfile()
        return await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
                p.arguments = ["-f", profile.path, claude, "-p",
                               "--output-format", "stream-json", "--verbose",
                               "--model", model, "--permission-mode", "bypassPermissions"]
                p.currentDirectoryURL = Paths.home.appendingPathComponent("Downloads")
                var env = ProcessInfo.processInfo.environment
                for k in env.keys where k.hasPrefix("ANTHROPIC_") { env.removeValue(forKey: k) }
                env["ANTHROPIC_BASE_URL"] = proxyBase
                env["ANTHROPIC_AUTH_TOKEN"] = authToken
                env["CLAUDE_CONFIG_DIR"] = Paths.config.path
                env["PATH"] = "\(Paths.localBin.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
                p.environment = env
                let inP = Pipe(), outP = Pipe(), errP = Pipe()
                p.standardInput = inP; p.standardOutput = outP; p.standardError = errP
                do { try p.run() } catch {
                    cont.resume(returning: (false, "Start fehlgeschlagen")); return
                }
                inP.fileHandleForWriting.write("Antworte mit genau: OK".data(using: .utf8)!)
                try? inP.fileHandleForWriting.close()

                let deadline = DispatchTime.now() + timeout
                let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: deadline, execute: killer)

                let data = outP.fileHandleForReading.readDataToEndOfFile()
                _ = errP.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                killer.cancel()

                var text = ""
                for line in String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) ?? [] {
                    guard let d = line.data(using: .utf8),
                          let e = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                          e["type"] as? String == "assistant",
                          let msg = e["message"] as? [String: Any],
                          let blocks = msg["content"] as? [[String: Any]] else { continue }
                    for b in blocks where b["type"] as? String == "text" {
                        text += (b["text"] as? String) ?? ""
                    }
                }
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty {
                    cont.resume(returning: (false, p.terminationStatus == 15 ? "Zeitüberschreitung" : "keine Antwort"))
                    return
                }
                for b in badText where t.contains(b) {
                    cont.resume(returning: (false, String(t.prefix(70)))); return
                }
                if t.lowercased().contains("rate limit") {
                    cont.resume(returning: (false, "Anbieter-Limit erreicht")); return
                }
                cont.resume(returning: (true, String(t.prefix(40))))
            }
        }
    }

    static func curatedModels() -> [String] {
        guard let d = try? Data(contentsOf: Paths.modelsJSON),
              let a = try? JSONDecoder().decode([String].self, from: d) else {
            return [Paths.defaultModel]
        }
        return a
    }

    /// Prueft das aktuelle Modell, wechselt bei Ausfall auf das naechste funktionierende.
    static func repairModel(current: String) async -> (changed: Bool, model: String, broken: Bool) {
        let (ok, _) = await testModelViaAgent(current)
        if ok { return (false, current, false) }
        for m in curatedModels() where m != current {
            let (ok2, _) = await testModelViaAgent(m)
            if ok2 { return (true, m, false) }
        }
        return (false, current, true)
    }

    // MARK: - Sandbox

    @discardableResult
    static func writeProfile() -> URL {
        let h = Paths.home.path
        let app = Paths.appBundle.path
        let p = """
        (version 1)
        (allow default)
        (deny file-write*
            (subpath "\(h)/.claude")
            (subpath "\(h)/Library/Application Support/Claude")
            (subpath "\(h)/.fcc")
            (subpath "\(h)/Library/LaunchAgents")
            (literal "\(h)/.zshrc") (literal "\(h)/.zprofile") (literal "\(h)/.zshenv")
            (literal "\(h)/.bash_profile") (literal "\(h)/.profile"))
        (deny file-write* (subpath "\(app)"))
        (allow file-write* (subpath "\(Paths.config.path)"))
        (deny file-write*
            (subpath "\(Paths.skills.path)")
            (subpath "\(Paths.skillsOff.path)")
            (subpath "\(Paths.chats.path)")
            (subpath "\(Paths.runtime.path)"))
        (deny file-read*
            (literal "\(Paths.fccEnv.path)")
            (subpath "\(h)/.ssh")
            (subpath "\(h)/.aws"))
        """
        try? FileManager.default.createDirectory(at: Paths.runtime, withIntermediateDirectories: true)
        try? p.write(to: Paths.profile, atomically: true, encoding: .utf8)
        return Paths.profile
    }

    // MARK: - Skills

    static func countSkills() -> Int {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: Paths.skills,
                        includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { u in
            !u.lastPathComponent.hasPrefix(".") &&
            ((try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false)
        }.count
    }

    static func skillDescription(_ dir: URL) -> String {
        guard let t = try? String(contentsOf: dir.appendingPathComponent("SKILL.md"), encoding: .utf8)
        else { return "" }
        for line in t.prefix(3000).components(separatedBy: .newlines) {
            if line.hasPrefix("description:") {
                return String(line.dropFirst(12))
                    .trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
            }
        }
        for line in t.prefix(3000).components(separatedBy: .newlines) where line.hasPrefix("# ") {
            return String(line.dropFirst(2))
        }
        return ""
    }

    static func listSkills() -> [SkillItem] {
        let fm = FileManager.default
        var out: [SkillItem] = []
        for (base, on) in [(Paths.skills, true), (Paths.skillsOff, false)] {
            let items = (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
            for u in items {
                guard !u.lastPathComponent.hasPrefix("."),
                      (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                else { continue }
                out.append(SkillItem(name: u.lastPathComponent, enabled: on,
                                     description: skillDescription(u)))
            }
        }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    static func toggleSkill(_ name: String, on: Bool) -> Bool {
        guard !name.contains("/"), !name.contains("..") else { return false }
        let src = (on ? Paths.skillsOff : Paths.skills).appendingPathComponent(name)
        let dst = (on ? Paths.skills : Paths.skillsOff).appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.path) else { return false }
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        return (try? fm.moveItem(at: src, to: dst)) != nil
    }

    static func importSkill(from src: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: src.appendingPathComponent("SKILL.md").path) else { return nil }
        let dst = Paths.skills.appendingPathComponent(src.lastPathComponent)
        if fm.fileExists(atPath: dst.path) { try? fm.removeItem(at: dst) }
        do { try fm.copyItem(at: src, to: dst); return src.lastPathComponent }
        catch { return nil }
    }

    // MARK: - Setup

    struct SetupState {
        var claude = false, claudeVersion = ""
        var uv = false, fcc = false, env = false, key = false
        var keyMasked = "", agent = false, proxy = false
        var dataDir = Paths.data.path
    }

    static func setupState() async -> SetupState {
        var s = SetupState()
        if let cb = claudeBin {
            s.claude = true
            let (_, out) = run(cb, ["--version"])
            s.claudeVersion = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        s.uv = which("uv") != nil
        s.fcc = FileManager.default.isExecutableFile(atPath: Paths.localBin.appendingPathComponent("fcc-server").path)
        s.env = FileManager.default.fileExists(atPath: Paths.fccEnv.path)
        let k = envValue("NVIDIA_NIM_API_KEY")
        s.key = !k.isEmpty
        s.keyMasked = k.count > 12 ? String(k.prefix(6)) + "..." + String(k.suffix(4)) : (k.isEmpty ? "" : "gesetzt")
        s.agent = FileManager.default.fileExists(atPath: Paths.launchAgent.path)
        s.proxy = await proxyUp()
        return s
    }

    /// Installiert fehlende Bestandteile. `log` wird auf dem Hauptthread aufgerufen.
    static func install(log: @escaping @Sendable (String) -> Void) async -> Bool {
        var ok = true
        func sh(_ launch: String, _ args: [String]) -> Bool {
            log("$ " + ([launch] + args).joined(separator: " "))
            let (rc, out) = run(launch, args, timeout: 900)
            for l in out.components(separatedBy: .newlines) where !l.isEmpty { log(l) }
            return rc == 0
        }
        if claudeBin == nil {
            log("== Claude Code CLI installieren ==")
            if let npm = which("npm") { ok = sh(npm, ["install", "-g", "@anthropic-ai/claude-code"]) && ok }
            else { log("npm fehlt. Bitte Node.js installieren: https://nodejs.org"); ok = false }
        } else { log("Claude Code CLI: bereits vorhanden") }

        if which("uv") == nil {
            log("== uv installieren ==")
            ok = sh("/bin/sh", ["-c", "curl -LsSf https://astral.sh/uv/install.sh | sh"]) && ok
        } else { log("uv: bereits vorhanden") }

        let fccPath = Paths.localBin.appendingPathComponent("fcc-server").path
        if !FileManager.default.isExecutableFile(atPath: fccPath) {
            log("== Proxy installieren ==")
            let uv = which("uv") ?? Paths.localBin.appendingPathComponent("uv").path
            ok = sh(uv, ["tool", "install",
                         "git+https://github.com/Alishahryar1/free-claude-code.git"]) && ok
        } else { log("Proxy: bereits vorhanden") }

        if !FileManager.default.fileExists(atPath: Paths.fccEnv.path) {
            log("== Konfiguration anlegen ==")
            envSet([:])
        }
        let n = mergeEnvTemplate()
        if n > 0 { log("== Konfiguration ergaenzt: \(n) Werte aus der Vorlage ==") }
        envSet(["HOST": "127.0.0.1"])

        if !FileManager.default.fileExists(atPath: Paths.launchAgent.path) {
            log("== Autostart einrichten ==")
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Label</key><string>com.freeclaudecode.server</string>
              <key>ProgramArguments</key><array><string>\(Paths.localBin.path)/fcc-server</string></array>
              <key>EnvironmentVariables</key><dict>
                <key>FCC_OPEN_BROWSER</key><string>false</string>
                <key>PATH</key><string>\(Paths.localBin.path):/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
              </dict>
              <key>WorkingDirectory</key><string>\(Paths.home.path)</string>
              <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
              <key>StandardOutPath</key><string>\(Paths.home.path)/.fcc/logs/launchd.out.log</string>
              <key>StandardErrorPath</key><string>\(Paths.home.path)/.fcc/logs/launchd.err.log</string>
            </dict></plist>
            """
            try? FileManager.default.createDirectory(
                at: Paths.home.appendingPathComponent(".fcc/logs"), withIntermediateDirectories: true)
            try? FileManager.default.createDirectory(
                at: Paths.launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plist.write(to: Paths.launchAgent, atomically: true, encoding: .utf8)
            run("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.launchAgent.path])
            log("Autostart aktiv")
        }
        log("== Proxy starten ==")
        let up = await ensureProxy(wait: 45)
        log(up ? "Proxy erreichbar" : "Proxy nicht erreichbar - Log: ~/.fcc/logs/server.log")
        log(ok && up ? "__DONE__" : "__DONE_ERR__")
        return ok && up
    }
}
