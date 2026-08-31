import Foundation

/// Preis- und Eignungsdaten zu einem Modell.
struct ModelInfo: Codable, Hashable {
    var promptPerToken: Double = 0      // USD je Eingabe-Token
    var completionPerToken: Double = 0  // USD je Ausgabe-Token
    var contextLength: Int = 0
    var name: String = ""

    /// Kosten je Million Eingabe-Token, wie es die Anbieter angeben.
    var promptPerMillion: Double { promptPerToken * 1_000_000 }
    var completionPerMillion: Double { completionPerToken * 1_000_000 }

    var isFree: Bool { promptPerToken == 0 && completionPerToken == 0 }

    /// Grobe Kosten einer typischen Claude-Code-Nachricht.
    /// Der System-Prompt mit allen Werkzeugen wiegt rund 45.000 Token.
    func estimatedMessageCost(inputTokens: Int = 45_000, outputTokens: Int = 400) -> Double {
        Double(inputTokens) * promptPerToken + Double(outputTokens) * completionPerToken
    }

    func cost(input: Int, output: Int) -> Double {
        Double(input) * promptPerToken + Double(output) * completionPerToken
    }
}

/// Kontostand bei einem Anbieter.
struct CreditInfo: Codable, Hashable {
    var usage: Double = 0
    var limit: Double? = nil
    var remaining: Double? = nil
    var checkedAt: Date = Date()
}

@MainActor
final class Pricing: ObservableObject {
    @Published private(set) var info: [String: ModelInfo] = [:]     // Schluessel: Modell-Basisname
    @Published private(set) var credits: CreditInfo? = nil
    @Published private(set) var loading = false

    private var file: URL { Paths.data.appendingPathComponent("pricing.json") }
    private var creditFile: URL { Paths.data.appendingPathComponent("credits.json") }

    init() { load() }

    func load() {
        if let d = try? Data(contentsOf: file),
           let m = try? JSONDecoder().decode([String: ModelInfo].self, from: d) { info = m }
        if let d = try? Data(contentsOf: creditFile),
           let c = try? JSONDecoder().decode(CreditInfo.self, from: d) { credits = c }
    }
    private func save() {
        if let d = try? JSONEncoder().encode(info) { try? d.write(to: file, options: .atomic) }
        if let c = credits, let d = try? JSONEncoder().encode(c) {
            try? d.write(to: creditFile, options: .atomic)
        }
    }

    func info(for modelID: String) -> ModelInfo? {
        let parts = modelID.components(separatedBy: "/")
        guard parts.count >= 3 else { return nil }
        return info[parts.dropFirst(2).joined(separator: "/")]
    }

    // MARK: - OpenRouter

    /// Holt Preise und Kontextlaenge fuer alle OpenRouter-Modelle.
    func refreshOpenRouter() async {
        let key = Backend.envValue("OPENROUTER_API_KEY")
        guard !key.isEmpty else { return }
        loading = true
        defer { loading = false }

        if let u = URL(string: "https://openrouter.ai/api/v1/models") {
            var r = URLRequest(url: u); r.timeoutInterval = 25
            r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            if let (d, _) = try? await URLSession.shared.data(for: r),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let arr = j["data"] as? [[String: Any]] {
                var next = info
                for m in arr {
                    guard let id = m["id"] as? String else { continue }
                    let p = m["pricing"] as? [String: Any] ?? [:]
                    next[id] = ModelInfo(
                        promptPerToken: Double(p["prompt"] as? String ?? "0") ?? 0,
                        completionPerToken: Double(p["completion"] as? String ?? "0") ?? 0,
                        contextLength: (m["context_length"] as? Int) ?? 0,
                        name: (m["name"] as? String) ?? id)
                }
                info = next
            }
        }
        await refreshCredits()
        save()
    }

    /// Liest Verbrauch und Limit des OpenRouter-Kontos.
    func refreshCredits() async {
        let key = Backend.envValue("OPENROUTER_API_KEY")
        guard !key.isEmpty, let u = URL(string: "https://openrouter.ai/api/v1/key") else { return }
        var r = URLRequest(url: u); r.timeoutInterval = 20
        r.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        guard let (d, _) = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let data = j["data"] as? [String: Any] else { return }
        var c = CreditInfo()
        c.usage = (data["usage"] as? Double) ?? 0
        c.limit = data["limit"] as? Double
        c.remaining = data["limit_remaining"] as? Double
        c.checkedAt = Date()
        credits = c
        save()
    }
}

// MARK: - Eignung fuers Programmieren

enum CodingScore {
    /// Einschaetzung 1-10, wie gut sich ein Modell als Coding-Agent schlaegt.
    /// Bewusst grob und von Hand gepflegt - es gibt keine Kennzahl dafuer.
    private static let table: [(String, Int)] = [
        ("claude-opus", 10), ("claude-sonnet-4.5", 10), ("claude-sonnet", 9),
        ("claude-haiku-4.5", 8), ("claude-haiku", 7), ("claude-fable", 9),
        ("gpt-5", 9), ("gpt-4.1-mini", 7), ("gpt-4.1", 9), ("gpt-4o-mini", 6), ("gpt-4o", 8),
        ("o3", 9), ("o4-mini", 8),
        ("gemini-2.5-pro", 9), ("gemini-2.5-flash", 7), ("gemini-2.0-flash", 6), ("gemini", 6),
        ("deepseek-r1", 8), ("deepseek-v3", 8), ("deepseek-chat", 8), ("deepseek-coder", 7),
        ("qwen3-coder", 8), ("qwen-2.5-coder", 7), ("qwen3", 7), ("qwen", 6),
        ("glm-4.6", 8), ("glm-4.5", 7), ("glm", 7),
        ("kimi-k2", 7), ("kimi", 6),
        ("grok-code", 8), ("grok", 7),
        ("codestral", 7), ("mistral-large", 6), ("mistral", 5),
        ("llama-3.3-70b", 6), ("llama-4", 7), ("llama", 5),
        ("gpt-oss-120b", 7), ("gpt-oss-20b", 5),
        ("nemotron-3-ultra", 6), ("nemotron-3-super", 6), ("nemotron-3.5", 6),
        ("nemotron-3-nano", 4), ("nemotron", 5),
        ("minimax", 6), ("command-r", 6), ("phi", 4), ("gemma", 4),
    ]

    static func score(for modelID: String) -> Int? {
        let low = modelID.lowercased()
        for (needle, value) in table where low.contains(needle) { return value }
        return nil
    }

    static func label(_ s: Int) -> String {
        switch s {
        case 9...10: return "hervorragend"
        case 7...8:  return "gut"
        case 5...6:  return "brauchbar"
        default:     return "schwach"
        }
    }
}
