import Foundation
import SwiftUI

// MARK: - Daten

struct ToolCall: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var input: String
    var result: String?
}

/// Eintrag der Aufgabenliste, die der Agent selbst pflegt.
struct TodoItem: Codable, Hashable, Identifiable {
    var id: String { text }
    var text: String
    var status: String      // pending | in_progress | completed
    var active: String = ""

    var symbol: String {
        switch status {
        case "completed":   return "checkmark.circle.fill"
        case "in_progress": return "circle.dotted"
        default:            return "circle"
        }
    }
}

struct Message: Codable, Identifiable, Hashable {
    var id = UUID()
    var role: String            // "user" | "assistant" | "system"
    var text: String
    var files: [String] = []
    var tools: [ToolCall] = []
    var ts: String = Message.now()
    var durationMs: Int? = nil
    var turns: Int? = nil
    var isError: Bool = false
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var costUSD: Double? = nil
    var thinking: String? = nil

    static func now() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: Date())
    }
}

struct Chat: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString.prefix(12).lowercased()
    var title: String = "Neuer Chat"
    var cwd: String
    var model: String
    var permission: String = "bypassPermissions"
    var sessionId: String? = nil
    /// Modell, mit dem die laufende Sitzung angelegt wurde. Wechselt das Modell,
    /// ist die Sitzung nicht mehr fortsetzbar und wird neu begonnen.
    var sessionModel: String? = nil
    var created: String = Chat.stamp()
    var updated: String = Chat.stamp()
    var messages: [Message] = []

    static func stamp() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: Date())
    }
}

struct AppState: Codable {
    var model: String = Paths.defaultModel
    var permission: String = "bypassPermissions"
    var lastDir: String = NSHomeDirectory() + "/Downloads"
}

struct SkillItem: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var enabled: Bool
    var description: String
}

struct ProviderKey: Identifiable {
    var id: String { key }
    /// Kennung, wie sie in Modell-IDs auftaucht (z.B. "nvidia_nim").
    var slug: String
    var key: String
    var label: String
    var url: String
    var required: Bool
    var isSet: Bool = false
    var masked: String = ""
    var free: String = ""
}

// MARK: - Pfade

enum Paths {
    static let defaultModel = "claude-3-freecc-no-thinking/nvidia_nim/nvidia/nemotron-3-super-120b-a12b"

    static var resources: URL {
        Bundle.main.resourceURL ?? URL(fileURLWithPath: ".")
    }
    static var appBundle: URL {
        Bundle.main.bundleURL
    }
    static let data: URL = {
        let inBundle = Paths.resources.appendingPathComponent("JPData")
        let fm = FileManager.default
        try? fm.createDirectory(at: inBundle, withIntermediateDirectories: true)
        let probe = inBundle.appendingPathComponent(".wtest")
        if (try? "x".write(to: probe, atomically: true, encoding: .utf8)) != nil {
            try? fm.removeItem(at: probe)
            return inBundle
        }
        let alt = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/JP Coding")
        try? fm.createDirectory(at: alt, withIntermediateDirectories: true)
        return alt
    }()
    static var chats: URL   { data.appendingPathComponent("chats") }
    static var config: URL  { data.appendingPathComponent("claude-config") }
    static var skills: URL  { config.appendingPathComponent("skills") }
    static var skillsOff: URL { config.appendingPathComponent("skills-disabled") }
    static var runtime: URL { data.appendingPathComponent("runtime") }
    static var stateFile: URL { data.appendingPathComponent("state.json") }
    static var profile: URL { runtime.appendingPathComponent("isolate.sb") }
    static var home: URL    { URL(fileURLWithPath: NSHomeDirectory()) }
    static var fccEnv: URL  { home.appendingPathComponent(".fcc/.env") }
    static var localBin: URL { home.appendingPathComponent(".local/bin") }
    static var launchAgent: URL {
        home.appendingPathComponent("Library/LaunchAgents/com.freeclaudecode.server.plist")
    }
    static var modelsJSON: URL { resources.appendingPathComponent("bin/models.json") }

    static func ensure() {
        let fm = FileManager.default
        for u in [chats, config, skills, skillsOff, runtime] {
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
        }
    }
}

enum Log {
    static let file: URL = {
        let d = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/JP Coding")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("debug.log")
    }()
    static func w(_ m: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(f.string(from: Date()))] \(m)\n"
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Store

@MainActor
final class Store: ObservableObject {
    @Published var chats: [Chat] = []
    @Published var currentID: String? = nil
    @Published var state = AppState()
    @Published var proxyOnline = false
    @Published var skillCount = 0
    @Published var models: [String] = []
    @Published var curated: [String] = []
    @Published var slashCommands: [String] = []
    @Published var busy = false
    @Published var toast: String? = nil
    @Published var toastBad = false
    @Published var needsSetup = false

    var current: Chat? {
        get { chats.first { $0.id == currentID } }
        set { if let v = newValue, let i = chats.firstIndex(where: { $0.id == v.id }) { chats[i] = v } }
    }

    init() {
        Paths.ensure()
        loadState()
        loadChats()
        curated = Backend.curatedModels()
        if state.model.isEmpty { state.model = curated.first ?? Paths.defaultModel }
    }

    // -- Persistenz
    func loadState() {
        if let d = try? Data(contentsOf: Paths.stateFile),
           let s = try? JSONDecoder().decode(AppState.self, from: d) { state = s }
    }
    func saveState() {
        do { try JSONEncoder().encode(state).write(to: Paths.stateFile, options: .atomic) }
        catch { Log.w("saveState FEHLER: \(error)") }
    }
    func loadChats() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.chats, includingPropertiesForKeys: nil)) ?? []
        var out: [Chat] = []
        for f in files where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let c = try? JSONDecoder().decode(Chat.self, from: d) {
                out.append(c)
            }
        }
        chats = out.sorted { $0.updated > $1.updated }
    }
    func save(_ c: Chat) {
        var c = c
        c.updated = Chat.stamp()
        if let i = chats.firstIndex(where: { $0.id == c.id }) { chats[i] = c } else { chats.insert(c, at: 0) }
        let url = Paths.chats.appendingPathComponent("\(c.id).json")
        do {
            try FileManager.default.createDirectory(at: Paths.chats, withIntermediateDirectories: true)
            let enc = JSONEncoder(); enc.outputFormatting = .prettyPrinted
            try enc.encode(c).write(to: url, options: .atomic)
            Log.w("save ok id=\(c.id) -> \(url.path)")
        } catch {
            Log.w("save FEHLER id=\(c.id) pfad=\(url.path) : \(error)")
            say("Chat konnte nicht gespeichert werden: \(error.localizedDescription)", bad: true)
        }
    }
    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: Paths.chats.appendingPathComponent("\(id).json"))
        chats.removeAll { $0.id == id }
        if currentID == id { currentID = chats.first?.id }
    }

    func newChat(cwd: String) -> Chat {
        Log.w("newChat cwd=\(cwd) dataDir=\(Paths.data.path)")
        let c = Chat(cwd: cwd, model: state.model, permission: state.permission)
        save(c); currentID = c.id
        state.lastDir = cwd; saveState()
        return c
    }

    /// Kompakter Gespraechsverlauf als Kontext fuer eine frische Sitzung.
    static func transcript(_ c: Chat, maxMessages: Int = 14, maxChars: Int = 700) -> String {
        let msgs = c.messages.suffix(maxMessages)
        guard !msgs.isEmpty else { return "" }
        var lines: [String] = ["Bisheriger Gespraechsverlauf (aelteste zuerst):"]
        for m in msgs {
            let who = m.role == "user" ? "Nutzer" : "Du"
            var t = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count > maxChars { t = String(t.prefix(maxChars)) + " [...]" }
            if !m.files.isEmpty {
                t += "\n(Anhaenge: " + m.files.map { URL(fileURLWithPath: $0).lastPathComponent }
                        .joined(separator: ", ") + ")"
            }
            if t.isEmpty { continue }
            lines.append("\(who): \(t)")
        }
        lines.append("")
        lines.append("--- Neue Nachricht des Nutzers ---")
        return lines.joined(separator: "\n")
    }

    /// Anbieter-Kennung aus einer Modell-ID: "anthropic/groq/llama-3.3" -> "groq"
    static func providerSlug(_ id: String) -> String {
        let parts = id.components(separatedBy: "/")
        return parts.count >= 3 ? parts[1] : ""
    }

    static func shortModel(_ m: String) -> String {
        m.replacingOccurrences(of: "claude-3-freecc-no-thinking/", with: "[fast] ")
         .replacingOccurrences(of: "anthropic/", with: "")
         .replacingOccurrences(of: "nvidia_nim/", with: "")
    }

    func say(_ m: String, bad: Bool = false) {
        toast = m; toastBad = bad
        Task { try? await Task.sleep(nanoseconds: bad ? 5_500_000_000 : 2_600_000_000)
               if toast == m { toast = nil } }
    }

    func refreshStatus() async {
        let up = await Backend.proxyUp()
        let n = Backend.countSkills()
        proxyOnline = up; skillCount = n
    }

    func refreshModels() async {
        let all = await Backend.allModels()
        models = all
    }
}
