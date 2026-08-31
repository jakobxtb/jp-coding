import Foundation

/// Ereignisse aus dem stream-json Ausgabeformat von Claude Code.
enum RunEvent {
    case initialized(model: String, tools: Int, sessionID: String?, slash: [String])
    case text(String)
    case tool(name: String, input: String)
    case toolResult(String)
    case done(ms: Int?, turns: Int?, isError: Bool, input: Int, output: Int)
    case failure(String)
}

@MainActor
final class Runner: ObservableObject {
    private var proc: Process?
    private(set) var running = false

    func stop() {
        proc?.terminate()
        proc = nil
        running = false
    }

    /// Startet Claude Code in der Sandbox und liefert Ereignisse per Callback.
    func run(chat: Chat, prompt: String,
             onEvent: @escaping @MainActor (RunEvent) -> Void,
             onFinish: @escaping @MainActor () -> Void) {

        let t0 = Date()
        guard let claude = Backend.claudeBin else {
            onEvent(.failure("Claude Code CLI nicht gefunden. Einstellungen > System > Fehlendes installieren."))
            onFinish(); return
        }
        let profile = Backend.writeProfile()

        var args = ["-f", profile.path, claude,
                    "-p", "--output-format", "stream-json", "--verbose",
                    "--model", chat.model,
                    "--permission-mode", chat.permission]
        // Fortsetzen nur, wenn die Sitzung vom selben Modell stammt. Eine Sitzung
        // eines anderen Anbieters laesst sich nicht zuverlaessig weiterfuehren.
        let canResume = (chat.sessionId?.isEmpty == false) && (chat.sessionModel == chat.model)
        if canResume, let sid = chat.sessionId { args += ["--resume", sid] }
        // Konnektoren: eigene mcp.json im App-Konfigordner, getrennt von der
        // Konfiguration des echten Claude.
        let mcp = Paths.config.appendingPathComponent("mcp.json")
        if FileManager.default.fileExists(atPath: mcp.path) {
            args += ["--mcp-config", mcp.path, "--strict-mcp-config"]
        }
        Log.w("runner: resume=\(canResume ? "ja" : "nein") sid=\(chat.sessionId ?? "-") sessionModel=\(chat.sessionModel ?? "-")")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        p.arguments = args
        var cwd = chat.cwd
        var isDir: ObjCBool = false
        if !(FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir) && isDir.boolValue) {
            cwd = Paths.home.appendingPathComponent("Downloads").path
        }
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)

        var env = ProcessInfo.processInfo.environment
        for k in env.keys where k.hasPrefix("ANTHROPIC_") { env.removeValue(forKey: k) }
        env["ANTHROPIC_BASE_URL"] = Backend.proxyBase
        env["ANTHROPIC_AUTH_TOKEN"] = Backend.authToken
        env["CLAUDE_CONFIG_DIR"] = Paths.config.path
        env["CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY"] = "1"
        env["CLAUDE_CODE_AUTO_COMPACT_WINDOW"] = "190000"
        env["PATH"] = "\(Paths.localBin.path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = errPipe

        // Der Lesehandler laeuft auf einem Hintergrund-Thread, der Beendigungshandler
        // auf einem anderen. Beide teilen sich diesen Puffer, deshalb gesperrt.
        let sink = LineSink()

        let firstByte = FirstFlag()
        outPipe.fileHandleForReading.readabilityHandler = { fh in
            let chunk = fh.availableData
            if chunk.isEmpty { return }
            if firstByte.mark() { Log.w("runner: erste Ausgabe nach \(String(format: "%.2f", Date().timeIntervalSince(t0)))s") }
            for lineData in sink.appendAndTakeLines(chunk) {
                guard let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                else { continue }
                let evs = Runner.parse(obj)
                Task { @MainActor in evs.forEach(onEvent) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { fh in
            sink.appendError(fh.availableData)
        }

        p.terminationHandler = { proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let err = sink.errorText().trimmingCharacters(in: .whitespacesAndNewlines)
            Log.w("runner: beendet nach \(String(format: "%.2f", Date().timeIntervalSince(t0)))s status=\(proc.terminationStatus)")
            Task { @MainActor in
                if proc.terminationStatus != 0 && !err.isEmpty {
                    onEvent(.failure(String(err.prefix(800))))
                }
                self.running = false
                self.proc = nil
                onFinish()
            }
        }

        Log.w("runner: starte \(claude) modell=\(chat.model) cwd=\(cwd)")
        do { try p.run() } catch {
            onEvent(.failure("Start fehlgeschlagen: \(error)")); onFinish(); return
        }
        Log.w("runner: Process gestartet nach \(String(format: "%.2f", Date().timeIntervalSince(t0)))s pid=\(p.processIdentifier)")
        proc = p; running = true

        // Sicherheitsnetz: haengt der Prozess, wird er beendet, damit die
        // Oberflaeche nicht stumm wartet.
        let hardLimit: TimeInterval = 300
        DispatchQueue.global().asyncAfter(deadline: .now() + hardLimit) { [weak p] in
            guard let p, p.isRunning else { return }
            Log.w("runner: harte Zeitgrenze \(Int(hardLimit))s erreicht, beende Prozess")
            p.terminate()
        }

        if let d = prompt.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(d)
        }
        try? inPipe.fileHandleForWriting.close()
    }

    // MARK: - Parsing

    nonisolated static func parse(_ e: [String: Any]) -> [RunEvent] {
        var out: [RunEvent] = []
        let type = e["type"] as? String ?? ""
        switch type {
        case "system":
            if e["subtype"] as? String == "init" {
                out.append(.initialized(
                    model: e["model"] as? String ?? "",
                    tools: (e["tools"] as? [Any])?.count ?? 0,
                    sessionID: e["session_id"] as? String,
                    slash: (e["slash_commands"] as? [String]) ?? []))
            }
        case "assistant":
            let msg = e["message"] as? [String: Any] ?? [:]
            for b in (msg["content"] as? [[String: Any]]) ?? [] {
                if b["type"] as? String == "text", let t = b["text"] as? String, !t.isEmpty {
                    out.append(.text(t))
                } else if b["type"] as? String == "tool_use" {
                    out.append(.tool(name: b["name"] as? String ?? "tool",
                                     input: shorten(b["input"], 190)))
                }
            }
        case "user":
            let msg = e["message"] as? [String: Any] ?? [:]
            for b in (msg["content"] as? [[String: Any]]) ?? [] where b["type"] as? String == "tool_result" {
                out.append(.toolResult(shorten(b["content"], 400)))
            }
        case "result":
            let u = e["usage"] as? [String: Any] ?? [:]
            let cacheRead = (u["cache_read_input_tokens"] as? Int) ?? 0
            let cacheWrite = (u["cache_creation_input_tokens"] as? Int) ?? 0
            out.append(.done(ms: e["duration_ms"] as? Int,
                             turns: e["num_turns"] as? Int,
                             isError: (e["is_error"] as? Bool) ?? false,
                             input: ((u["input_tokens"] as? Int) ?? 0) + cacheRead + cacheWrite,
                             output: (u["output_tokens"] as? Int) ?? 0))
        default: break
        }
        return out
    }

    nonisolated static func shorten(_ v: Any?, _ n: Int) -> String {
        var s: String
        if let str = v as? String { s = str }
        else if let v, let d = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]) {
            s = String(data: d, encoding: .utf8) ?? ""
        } else { s = "" }
        s = s.replacingOccurrences(of: "\n", with: " ")
        return s.count > n ? String(s.prefix(n)) + "..." : s
    }
}

/// Thread-sicherer Zeilenpuffer: der Lesehandler und der Beendigungshandler
/// laufen auf unterschiedlichen Threads und greifen beide darauf zu.
final class LineSink: @unchecked Sendable {
    private let lock = NSLock()
    private var out = Data()
    private var err = ""

    /// Haengt Daten an und liefert alle vollstaendigen Zeilen zurueck.
    func appendAndTakeLines(_ chunk: Data) -> [Data] {
        lock.lock(); defer { lock.unlock() }
        out.append(chunk)
        var lines: [Data] = []
        while let idx = out.firstIndex(of: 0x0A) {
            let line = out.subdata(in: out.startIndex..<idx)
            out.removeSubrange(out.startIndex...idx)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    func appendError(_ d: Data) {
        guard let s = String(data: d, encoding: .utf8), !s.isEmpty else { return }
        lock.lock(); err += s; lock.unlock()
    }

    func errorText() -> String {
        lock.lock(); defer { lock.unlock() }
        return err
    }
}


/// Einmal-Markierung, thread-sicher.
final class FirstFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func mark() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true; return true
    }
}
