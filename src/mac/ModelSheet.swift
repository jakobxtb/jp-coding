import SwiftUI

struct ModelSheet: View {
    @ObservedObject var store: Store
    @ObservedObject var probe: ModelProbe
    @ObservedObject var pricing: Pricing
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var onlyWorking = false
    @State private var reasoning = false
    @State private var provider = ""
    @State private var sortByScore = true
    @State private var keys: [ProviderKey] = []

    private var prefix: String {
        reasoning ? "anthropic/" : "claude-3-freecc-no-thinking/"
    }

    /// Modelle je Anbieter, auf den Grundnamen dedupliziert.
    private var byProvider: [String: [String]] {
        var out: [String: Set<String>] = [:]
        for id in store.models {
            let parts = id.components(separatedBy: "/")
            guard parts.count >= 3 else { continue }
            out[parts[1], default: []].insert(parts.dropFirst(2).joined(separator: "/"))
        }
        return out.mapValues { Array($0).sorted() }
    }

    private var activeProvider: String {
        if !provider.isEmpty { return provider }
        let cur = Store.providerSlug(store.state.model)
        return cur.isEmpty ? (byProvider.keys.sorted().first ?? "nvidia_nim") : cur
    }

    private func fullID(_ base: String) -> String { prefix + activeProvider + "/" + base }

    private var visibleModels: [String] {
        var list = byProvider[activeProvider] ?? []
        if !query.isEmpty { list = list.filter { $0.localizedCaseInsensitiveContains(query) } }
        if onlyWorking { list = list.filter { probe.result(for: fullID($0))?.ok == true } }
        if sortByScore {
            list.sort { a, b in
                let sa = CodingScore.score(for: a) ?? 0, sb = CodingScore.score(for: b) ?? 0
                if sa != sb { return sa > sb }
                return a < b
            }
        }
        return list
    }

    private var curatedBases: Set<String> {
        Set(store.curated
            .filter { Store.providerSlug($0) == activeProvider }
            .compactMap { id -> String? in
                let p = id.components(separatedBy: "/")
                return p.count >= 3 ? p.dropFirst(2).joined(separator: "/") : nil
            })
    }

    var body: some View {
        SheetFrame(title: "MODELL WAEHLEN", width: 820, height: 640) {
            VStack(spacing: 0) {
                providerBar
                Divider().overlay(Theme.stroke2)
                controls
                Divider().overlay(Theme.stroke2)
                list
            }
        }
        .task {
            await store.refreshModels()
            if pricing.info.isEmpty { await pricing.refreshOpenRouter() }
            keys = Backend.providers.map { p in
                var q = p; q.isSet = !Backend.envValue(p.key).isEmpty; return q
            }
        }
    }

    private var providerBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(keys) { p in
                    let count = byProvider[p.slug]?.count ?? 0
                    let on = activeProvider == p.slug
                    Button { provider = p.slug; query = "" } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(count > 0 ? Theme.green : (p.isSet ? Theme.warn : Theme.muted.opacity(0.4)))
                                .frame(width: 6, height: 6)
                            Text(p.label).font(Theme.f(11, on ? .semibold : .regular))
                            Text(count > 0 ? "\(count)" : (p.isSet ? "0" : "–"))
                                .font(Theme.f(9.5)).foregroundColor(Theme.muted)
                        }
                    }
                    .buttonStyle(JPButton(prominent: on))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .frame(height: 48)
    }

    private var controls: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                TextField("Modelle durchsuchen ...", text: $query)
                    .textFieldStyle(.plain).font(Theme.f(12))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
                Toggle("nur funktionierende", isOn: $onlyWorking)
                    .toggleStyle(.checkbox).font(Theme.f(11)).foregroundColor(Theme.muted)
                Toggle("nach Eignung", isOn: $sortByScore)
                    .toggleStyle(.checkbox).font(Theme.f(11)).foregroundColor(Theme.muted)
                Toggle("Reasoning", isOn: $reasoning)
                    .toggleStyle(.checkbox).font(Theme.f(11)).foregroundColor(Theme.muted)
                    .help("Aus ist fuer Agentenbetrieb meist besser und schneller")
            }
            HStack(spacing: 8) {
                if probe.sweepRunning {
                    Button("Abbrechen") { probe.cancelSweep() }.buttonStyle(JPButton(danger: true))
                    ProgressView(value: Double(probe.sweepDone), total: Double(max(1, probe.sweepTotal)))
                        .frame(width: 130)
                    Text("\(probe.sweepDone)/\(probe.sweepTotal)")
                        .font(Theme.f(10.5)).foregroundColor(Theme.muted)
                } else {
                    Button("Sichtbare testen") {
                        probe.sweep(Array(visibleModels.prefix(12)).map { fullID($0) }, timeout: 90)
                    }
                    .buttonStyle(JPButton(prominent: true))
                    .disabled(visibleModels.isEmpty)
                    let ok = probe.workingModels().filter { Store.providerSlug($0) == activeProvider }.count
                    Text("\(ok) bestaetigt bei \(Backend.providerLabel(activeProvider))")
                        .font(Theme.f(10.5)).foregroundColor(ok > 0 ? Theme.green : Theme.muted)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    @ViewBuilder private var list: some View {
        if visibleModels.isEmpty {
            emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    let curated = visibleModels.filter { curatedBases.contains($0) }
                    let rest = visibleModels.filter { !curatedBases.contains($0) }
                    if !curated.isEmpty {
                        header("Getestet und empfohlen")
                        ForEach(curated, id: \.self) { row($0) }
                    }
                    if !rest.isEmpty {
                        header(curated.isEmpty ? "Verfuegbar (\(rest.count))"
                                               : "Weitere (\(rest.count), ungetestet)")
                        ForEach(rest, id: \.self) { row($0) }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
    }

    private func header(_ t: String) -> some View {
        Text(t).font(Theme.f(10)).foregroundColor(Theme.muted).tracking(1.2)
            .padding(.top, 6).padding(.bottom, 2)
    }

    private var emptyState: some View {
        let p = keys.first { $0.slug == activeProvider }
        return VStack(spacing: 12) {
            Image(systemName: (p?.isSet ?? false) ? "exclamationmark.triangle" : "key")
                .font(.system(size: 26)).foregroundColor(Theme.muted.opacity(0.6))
            if let p, !p.isSet {
                Text("Kein Schluessel fuer \(p.label)")
                    .font(Theme.f(13)).foregroundColor(Theme.text)
                if !p.free.isEmpty {
                    Text(p.free).font(Theme.f(11)).foregroundColor(Theme.green.opacity(0.85))
                }
                Text("Schluessel in den Einstellungen eintragen. Danach startet der Proxy neu\nund die Modelle dieses Anbieters erscheinen hier automatisch.")
                    .font(Theme.f(11)).foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center).lineSpacing(4)
                Link("Schluessel holen", destination: URL(string: p.url)!)
                    .font(Theme.f(11.5)).foregroundColor(Theme.green)
            } else if let p {
                Text("Schluessel fuer \(p.label) gesetzt, aber keine Modelle gemeldet")
                    .font(Theme.f(12.5)).foregroundColor(Theme.text)
                Text("Der Anbieter lehnt den Schluessel moeglicherweise ab.\nEinstellungen > System > Proxy neu starten, dann erneut pruefen.")
                    .font(Theme.f(11)).foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center).lineSpacing(4)
            } else {
                Text("Keine Modelle").font(Theme.f(12)).foregroundColor(Theme.muted)
            }
        }
        .padding(30)
    }

    private func row(_ base: String) -> some View {
        let id = fullID(base)
        let active = id == store.state.model
        let r = probe.result(for: id)
        let busy = probe.isTesting(id)
        return HStack(spacing: 9) {
            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 11))
                .foregroundColor(active ? Theme.green : Theme.muted.opacity(0.45))

            if let sc = CodingScore.score(for: base) {
                Text("\(sc)")
                    .font(Theme.f(11, .semibold))
                    .foregroundColor(sc >= 9 ? Theme.green : (sc >= 7 ? Theme.text : Theme.muted))
                    .frame(width: 20)
                    .help("Eignung fuers Programmieren: \(sc)/10 (\(CodingScore.label(sc)))")
            } else {
                Text("–").font(Theme.f(11)).foregroundColor(Theme.muted.opacity(0.4)).frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(base).font(Theme.f(12))
                        .foregroundColor(active ? Theme.green : Theme.text).lineLimit(1)
                    if let inf = pricing.info[base] {
                        if inf.isFree {
                            Text("gratis").font(Theme.f(9.5)).foregroundColor(Theme.green.opacity(0.9))
                        } else {
                            Text(String(format: "~$%.3f/Nachricht", inf.estimatedMessageCost()))
                                .font(Theme.f(9.5)).foregroundColor(Theme.warn.opacity(0.85))
                                .help(String(format: "%.2f $/M ein, %.2f $/M aus, Kontext %d",
                                             inf.promptPerMillion, inf.completionPerMillion, inf.contextLength))
                        }
                    }
                }
                if let r {
                    Text(r.ok ? "Werkzeuge OK in \(String(format: "%.1f", Double(r.ms)/1000))s"
                              + (r.ms > 20000 ? "  (langsam)" : "") + "  ·  \(r.age)"
                              : "faellt aus: \(r.detail)  ·  \(r.age)")
                        .font(Theme.f(9.5))
                        .foregroundColor(r.ok ? Theme.green.opacity(0.8) : Theme.red.opacity(0.85))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            if busy {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 30)
            } else if let r {
                Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 12)).foregroundColor(r.ok ? Theme.green : Theme.red)
            } else {
                Text("?").font(Theme.f(11)).foregroundColor(Theme.muted.opacity(0.6)).frame(width: 12)
            }

            Button("TEST") { Task { await probe.test(id) } }
                .buttonStyle(JPButton()).disabled(busy || probe.sweepRunning)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(active ? Theme.green.opacity(0.1) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(active ? Theme.green.opacity(0.3) : Theme.stroke2, lineWidth: 1)))
        .contentShape(Rectangle())
        .onTapGesture { onPick(id); dismiss() }
        .opacity(r?.ok == false ? 0.62 : 1)
    }
}
