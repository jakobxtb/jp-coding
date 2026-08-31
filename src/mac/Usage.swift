import SwiftUI

/// Auswertung ueber alle Chats: Kosten, Token, Modelle.
struct UsageStats {
    struct Row: Identifiable {
        var id: String { key }
        var key: String
        var messages: Int = 0
        var input: Int = 0
        var output: Int = 0
        var cost: Double = 0
    }
    var totalMessages = 0
    var totalInput = 0
    var totalOutput = 0
    var totalCost: Double = 0
    var byModel: [Row] = []
    var byChat: [Row] = []

    @MainActor
    static func compute(_ chats: [Chat]) -> UsageStats {
        var s = UsageStats()
        var models: [String: Row] = [:]
        var perChat: [String: Row] = [:]
        for c in chats {
            var cr = perChat[c.id] ?? Row(key: c.title.isEmpty ? c.id : c.title)
            for m in c.messages where m.role == "assistant" {
                let inTok = m.inputTokens ?? 0
                let outTok = m.outputTokens ?? 0
                let cost = m.costUSD ?? 0
                s.totalMessages += 1
                s.totalInput += inTok; s.totalOutput += outTok; s.totalCost += cost
                cr.messages += 1; cr.input += inTok; cr.output += outTok; cr.cost += cost

                let mk = Store.shortModel(c.model)
                var mr = models[mk] ?? Row(key: mk)
                mr.messages += 1; mr.input += inTok; mr.output += outTok; mr.cost += cost
                models[mk] = mr
            }
            perChat[c.id] = cr
        }
        s.byModel = models.values.sorted { $0.cost == $1.cost ? $0.messages > $1.messages : $0.cost > $1.cost }
        s.byChat = perChat.values.filter { $0.messages > 0 }
            .sorted { $0.cost == $1.cost ? $0.messages > $1.messages : $0.cost > $1.cost }
        return s
    }
}

func fmtTok(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}
func fmtUSD(_ c: Double) -> String {
    c == 0 ? "—" : (c < 0.01 ? String(format: "$%.4f", c) : String(format: "$%.3f", c))
}

// MARK: - Nutzungsfenster

struct UsageSheet: View {
    @ObservedObject var store: Store
    @ObservedObject var pricing: Pricing

    private var stats: UsageStats { UsageStats.compute(store.chats) }

    var body: some View {
        SheetFrame(title: "NUTZUNG", width: 720, height: 600) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    tiles
                    if let c = pricing.credits { account(c) }
                    section("Nach Modell", stats.byModel)
                    section("Nach Chat", stats.byChat)
                    Text("Kosten werden aus der gemeldeten Tokennutzung mal dem Anbieterpreis "
                       + "berechnet. Fuer Modelle ohne hinterlegten Preis bleibt die Spalte leer.")
                        .font(Theme.f(10.5)).foregroundColor(Theme.muted).lineSpacing(4)
                }
                .padding(18)
            }
        }
        .task { await pricing.refreshCredits() }
    }

    private var tiles: some View {
        HStack(spacing: 10) {
            tile("Nachrichten", "\(stats.totalMessages)")
            tile("Eingabe", fmtTok(stats.totalInput))
            tile("Ausgabe", fmtTok(stats.totalOutput))
            tile("Kosten", fmtUSD(stats.totalCost), accent: true)
        }
    }

    private func tile(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(Theme.f(10)).foregroundColor(Theme.muted).tracking(1.1)
            Text(value).font(Theme.f(18, .semibold))
                .foregroundColor(accent ? Theme.green : Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.glass2)
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.stroke2, lineWidth: 1)))
    }

    private func account(_ c: CreditInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OPENROUTER-KONTO").font(Theme.f(10)).foregroundColor(Theme.muted).tracking(1.2)
            HStack(spacing: 10) {
                tile("verbraucht", String(format: "$%.4f", c.usage))
                if let rem = c.remaining { tile("verfuegbar", String(format: "$%.2f", rem), accent: true) }
                if let lim = c.limit { tile("Limit", String(format: "$%.2f", lim)) }
            }
            if let rem = c.remaining, rem > 0 {
                let used = c.usage / max(c.usage + rem, 0.0001)
                ProgressView(value: min(max(used, 0), 1)).tint(Theme.green)
            }
        }
    }

    private func section(_ title: String, _ rows: [UsageStats.Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.f(10)).foregroundColor(Theme.muted).tracking(1.2)
            if rows.isEmpty {
                Text("noch nichts").font(Theme.f(11)).foregroundColor(Theme.muted.opacity(0.7))
            } else {
                HStack(spacing: 0) {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Nachr.").frame(width: 62, alignment: .trailing)
                    Text("ein").frame(width: 62, alignment: .trailing)
                    Text("aus").frame(width: 62, alignment: .trailing)
                    Text("Kosten").frame(width: 78, alignment: .trailing)
                }
                .font(Theme.f(9.5)).foregroundColor(Theme.muted.opacity(0.8))
                ForEach(rows.prefix(12)) { r in
                    HStack(spacing: 0) {
                        Text(r.key).font(Theme.f(11.5)).foregroundColor(Theme.text)
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(r.messages)").frame(width: 62, alignment: .trailing)
                        Text(fmtTok(r.input)).frame(width: 62, alignment: .trailing)
                        Text(fmtTok(r.output)).frame(width: 62, alignment: .trailing)
                        Text(fmtUSD(r.cost)).foregroundColor(r.cost > 0 ? Theme.green : Theme.muted)
                            .frame(width: 78, alignment: .trailing)
                    }
                    .font(Theme.f(11))
                    .foregroundColor(Theme.muted)
                    .padding(.vertical, 5)
                    .overlay(Rectangle().frame(height: 1)
                        .foregroundColor(Color.white.opacity(0.04)), alignment: .bottom)
                }
            }
        }
    }
}

// MARK: - Skill-Auswahl

struct SkillPickerSheet: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [SkillItem] = []
    @State private var query = ""

    private var filtered: [SkillItem] {
        let active = items.filter { $0.enabled }
        guard !query.isEmpty else { return active }
        return active.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        SheetFrame(title: "SKILL EINSETZEN", width: 700, height: 560) {
            VStack(spacing: 10) {
                TextField("Skill suchen ...", text: $query)
                    .textFieldStyle(.plain).font(Theme.f(12))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
                    .padding(.horizontal, 18).padding(.top, 12)

                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 24))
                            .foregroundColor(Theme.muted.opacity(0.6))
                        Text(items.isEmpty ? "Keine Skills im Paket" : "Kein Treffer")
                            .font(Theme.f(12)).foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(filtered) { s in
                                Button {
                                    onPick(s.name); dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("/" + s.name).font(Theme.f(12, .medium))
                                            .foregroundColor(Theme.green)
                                        if !s.description.isEmpty {
                                            Text(s.description).font(Theme.f(10.5))
                                                .foregroundColor(Theme.muted)
                                                .lineLimit(2)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(RoundedRectangle(cornerRadius: 9)
                                        .strokeBorder(Theme.stroke2, lineWidth: 1))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18).padding(.bottom, 16)
                    }
                }
            }
        }
        .onAppear { items = Backend.listSkills() }
    }
}
