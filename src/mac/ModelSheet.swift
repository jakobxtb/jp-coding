import SwiftUI

struct ModelSheet: View {
    @ObservedObject var store: Store
    @ObservedObject var probe: ModelProbe
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var onlyWorking = false

    private var others: [String] {
        store.models.filter { $0.hasPrefix("anthropic/") && !store.curated.contains($0) }
    }
    private func visible(_ list: [String]) -> [String] {
        var l = list
        if !query.isEmpty { l = l.filter { $0.localizedCaseInsensitiveContains(query) } }
        if onlyWorking { l = l.filter { probe.result(for: $0)?.ok == true } }
        return l
    }

    var body: some View {
        SheetFrame(title: "MODELL WAEHLEN", width: 780, height: 600) {
            VStack(spacing: 0) {
                controls
                Divider().overlay(Theme.stroke2)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        section("Mitgeliefert (Grundstock)", visible(store.curated))
                        section("Alle uebrigen (\(others.count) bei NVIDIA gemeldet)", visible(others))
                        if store.models.isEmpty {
                            Text("Keine Modellliste vom Proxy. Ist er online?")
                                .font(Theme.f(11)).foregroundColor(Theme.muted).padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 12)
                }
            }
        }
        .task { await store.refreshModels() }
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
            }
            HStack(spacing: 8) {
                if probe.sweepRunning {
                    Button("Abbrechen") { probe.cancelSweep() }.buttonStyle(JPButton(danger: true))
                    ProgressView(value: Double(probe.sweepDone), total: Double(max(1, probe.sweepTotal)))
                        .frame(width: 150)
                    Text("\(probe.sweepDone)/\(probe.sweepTotal) getestet")
                        .font(Theme.f(10.5)).foregroundColor(Theme.muted)
                } else {
                    Button("Grundstock testen") {
                        probe.sweep(store.curated, timeout: 90)
                    }.buttonStyle(JPButton(prominent: true))
                    Button("ALLE testen (dauert)") {
                        probe.sweep(store.curated + others, timeout: 60)
                    }.buttonStyle(JPButton())
                    let ok = probe.workingModels().count
                    Text("\(ok) bestaetigt funktionierend")
                        .font(Theme.f(10.5)).foregroundColor(ok > 0 ? Theme.green : Theme.muted)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func section(_ title: String, _ list: [String]) -> some View {
        Group {
            if !list.isEmpty {
                Text(title).font(Theme.f(10)).foregroundColor(Theme.muted).tracking(1.2)
                    .padding(.top, 8).padding(.bottom, 2)
                ForEach(list, id: \.self) { m in row(m) }
            }
        }
    }

    private func row(_ m: String) -> some View {
        let active = m == store.state.model
        let r = probe.result(for: m)
        let busy = probe.isTesting(m)
        return HStack(spacing: 9) {
            Image(systemName: active ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 11))
                .foregroundColor(active ? Theme.green : Theme.muted.opacity(0.45))

            VStack(alignment: .leading, spacing: 2) {
                Text(Store.shortModel(m))
                    .font(Theme.f(12)).foregroundColor(active ? Theme.green : Theme.text).lineLimit(1)
                if let r {
                    Text(r.ok ? "antwortet in \(String(format: "%.1f", Double(r.ms)/1000))s"
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
                    .font(.system(size: 12))
                    .foregroundColor(r.ok ? Theme.green : Theme.red)
            } else {
                Text("?").font(Theme.f(11)).foregroundColor(Theme.muted.opacity(0.6)).frame(width: 12)
            }

            Button("TEST") { Task { await probe.test(m) } }
                .buttonStyle(JPButton()).disabled(busy || probe.sweepRunning)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(active ? Theme.green.opacity(0.1) : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(active ? Theme.green.opacity(0.3) : Theme.stroke2, lineWidth: 1)))
        .contentShape(Rectangle())
        .onTapGesture { onPick(m); dismiss() }
        .opacity(r?.ok == false ? 0.62 : 1)
    }
}
