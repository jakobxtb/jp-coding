import SwiftUI
import AppKit

// MARK: - Rahmen

struct SheetFrame<Content: View>: View {
    let title: String
    var width: CGFloat = 620
    var height: CGFloat = 520
    var trailing: AnyView? = nil
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(Theme.f(13.5, .semibold)).foregroundColor(Theme.green).tracking(1.4)
                Spacer()
                if let t = trailing { t }
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11)) }
                    .buttonStyle(.plain).foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            Divider().overlay(Theme.stroke2)
            content
        }
        .frame(width: width, height: height)
        .background(Theme.panel)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Einstellungen

struct SettingsSheet: View {
    @ObservedObject var store: Store
    @State private var tab = 0
    @State private var keys: [ProviderKey] = []
    @State private var entry: [String: String] = [:]
    @State private var setup = Backend.SetupState()
    @State private var log = ""
    @State private var installing = false

    var body: some View {
        SheetFrame(title: "EINSTELLUNGEN", width: 660, height: 560) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    tabButton("API-Schluessel", 0)
                    tabButton("System", 1)
                    tabButton("Info", 2)
                }
                .padding(.horizontal, 18).padding(.vertical, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if tab == 0 { keysPane } else if tab == 1 { systemPane } else { infoPane }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 20)
                }
            }
        }
        .task { await reload() }
    }

    private func tabButton(_ t: String, _ i: Int) -> some View {
        Button(t) { tab = i }.buttonStyle(JPButton(prominent: tab == i))
    }

    private func reload() async {
        keys = Backend.providers.map { p in
            var q = p
            let v = Backend.envValue(p.key)
            q.isSet = !v.isEmpty
            q.masked = v.count > 12 ? String(v.prefix(6)) + "..." + String(v.suffix(4))
                                    : (v.isEmpty ? "" : "gesetzt")
            return q
        }
        setup = await Backend.setupState()
    }

    private var keysPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schluessel liegen lokal in ~/.fcc/.env und gehen nur an den jeweiligen Anbieter. "
               + "Nach dem Speichern startet der Proxy neu.")
                .font(Theme.f(11)).foregroundColor(Theme.muted).lineSpacing(4)
                .padding(.bottom, 4)

            ForEach(keys) { p in
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(p.label + (p.required ? "  (erforderlich)" : ""))
                            .font(Theme.f(12, .medium)).foregroundColor(Theme.text)
                        Spacer()
                        Text(p.isSet ? p.masked : "nicht gesetzt")
                            .font(Theme.f(10.5)).foregroundColor(p.isSet ? Theme.green : Theme.muted)
                    }
                    HStack(spacing: 7) {
                        SecureField("Schluessel einfuegen ...", text: Binding(
                            get: { entry[p.key] ?? "" },
                            set: { entry[p.key] = $0 }))
                            .textFieldStyle(.plain).font(Theme.f(12))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.45))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke, lineWidth: 1)))
                        Button("Speichern") { save(p) }.buttonStyle(JPButton(prominent: true))
                    }
                    Link("Schluessel holen", destination: URL(string: p.url)!)
                        .font(Theme.f(10.5)).foregroundColor(Theme.green)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke2, lineWidth: 1))
            }
        }
    }

    private func save(_ p: ProviderKey) {
        let v = (entry[p.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { store.say("Kein Wert eingegeben", bad: true); return }
        Backend.envSet([p.key: v])
        entry[p.key] = ""
        store.say(p.label + " gespeichert, Proxy startet neu ...")
        Task {
            let ok = await Backend.restartProxy()
            await store.refreshStatus()
            await store.refreshModels()
            await reload()
            store.say(ok ? "Proxy laeuft" : "Proxy nicht erreichbar", bad: !ok)
        }
    }

    private var systemPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            checkRow("Claude Code CLI", setup.claude, setup.claudeVersion.isEmpty ? "nicht gefunden" : setup.claudeVersion)
            checkRow("uv (Paketmanager)", setup.uv, setup.uv ? "installiert" : "fehlt")
            checkRow("Proxy installiert", setup.fcc, setup.fcc ? "installiert" : "fehlt")
            checkRow("Konfiguration", setup.env, setup.env ? "~/.fcc/.env" : "fehlt")
            checkRow("NVIDIA-Schluessel", setup.key, setup.keyMasked.isEmpty ? "nicht gesetzt" : setup.keyMasked)
            checkRow("Autostart", setup.agent, setup.agent ? "aktiv" : "fehlt")
            checkRow("Proxy laeuft", setup.proxy, setup.proxy ? "online" : "offline")

            HStack(spacing: 8) {
                Button(installing ? "laeuft ..." : "Fehlendes installieren") { install() }
                    .buttonStyle(JPButton(prominent: true)).disabled(installing)
                Button("Proxy neu starten") {
                    Task { store.say("Proxy startet neu ...")
                           let ok = await Backend.restartProxy()
                           await store.refreshStatus(); await reload()
                           store.say(ok ? "Proxy laeuft" : "Proxy offline", bad: !ok) }
                }.buttonStyle(JPButton())
                Button("Modell reparieren") {
                    Task { let r = await Backend.repairModel(current: store.state.model)
                           if r.changed { store.state.model = r.model; store.saveState()
                                          store.say("gewechselt auf " + r.model) }
                           else if r.broken { store.say("Kein Modell erreichbar", bad: true) }
                           else { store.say("Modell ist in Ordnung") } }
                }.buttonStyle(JPButton())
            }
            .padding(.top, 12)

            if !log.isEmpty {
                ScrollView {
                    Text(log).font(Theme.f(10.5))
                        .foregroundColor(Color(red: 0.62, green: 0.85, blue: 0.74))
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .frame(height: 190)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.5))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
                .padding(.top, 10)
            }
        }
    }

    private func install() {
        installing = true; log = ""
        Task {
            _ = await Backend.install { line in
                Task { @MainActor in
                    if line == "__DONE__" || line == "__DONE_ERR__" { return }
                    log += line + "\n"
                }
            }
            installing = false
            await store.refreshStatus(); await store.refreshModels(); await reload()
            store.say("Installation abgeschlossen")
        }
    }

    private func checkRow(_ n: String, _ ok: Bool, _ detail: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: ok ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(ok ? Theme.green : Theme.red).frame(width: 16)
            Text(n).font(Theme.f(12)).foregroundColor(Theme.text)
            Spacer()
            Text(detail).font(Theme.f(10.5)).foregroundColor(Theme.muted).lineLimit(1)
        }
        .padding(.vertical, 7)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.04)), alignment: .bottom)
    }

    private var infoPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            kv("Version", "1.0 (nativ)")
            kv("Datenordner", Paths.data.path)
            kv("Proxy", Backend.proxyBase)
            kv("Claude Code", setup.claudeVersion.isEmpty ? "nicht gefunden" : setup.claudeVersion)
            kv("Skills aktiv", "\(store.skillCount)")
            Text("JP Coding startet Claude Code in einer macOS-Sandbox. Schreibzugriff auf "
               + "~/.claude, Shell-Profile und die Schluesseldatei ist auf Kernel-Ebene gesperrt.")
                .font(Theme.f(11)).foregroundColor(Theme.muted).lineSpacing(4).padding(.top, 10)
        }
    }

    private func kv(_ l: String, _ r: String) -> some View {
        HStack {
            Text(l).font(Theme.f(11.5)).foregroundColor(Theme.muted)
            Spacer()
            Text(r).font(Theme.f(11.5)).foregroundColor(Theme.text)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(.vertical, 6)
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.04)), alignment: .bottom)
    }
}

// MARK: - Skills

struct SkillsSheet: View {
    @ObservedObject var store: Store
    @State private var items: [SkillItem] = []
    @State private var query = ""

    var filtered: [SkillItem] {
        query.isEmpty ? items : items.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.description.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        SheetFrame(title: "SKILLS", width: 780, height: 580,
                   trailing: AnyView(Button("Skill importieren") { importSkill() }.buttonStyle(JPButton()))) {
            VStack(spacing: 10) {
                TextField("Skills durchsuchen ...", text: $query)
                    .textFieldStyle(.plain).font(Theme.f(12))
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
                    .padding(.horizontal, 18).padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(filtered) { s in row(s) }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 16)
                }
            }
        }
        .onAppear { items = Backend.listSkills() }
    }

    private func row(_ s: SkillItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.name).font(Theme.f(12)).foregroundColor(Theme.text)
                if !s.description.isEmpty {
                    Text(s.description).font(Theme.f(10.5)).foregroundColor(Theme.muted)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(s.enabled ? 1 : 0.45)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { s.enabled },
                set: { on in
                    if Backend.toggleSkill(s.name, on: on) {
                        items = Backend.listSkills()
                        Task { await store.refreshStatus() }
                    } else { store.say("Konnte Skill nicht umschalten", bad: true) }
                }))
                .labelsHidden().toggleStyle(.switch).tint(Theme.green)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke2, lineWidth: 1))
    }

    private func importSkill() {
        let p = NSOpenPanel()
        p.message = "Skill-Ordner waehlen (muss SKILL.md enthalten)"
        p.canChooseDirectories = true; p.canChooseFiles = false
        guard p.runModal() == .OK, let u = p.url else { return }
        if let n = Backend.importSkill(from: u) {
            items = Backend.listSkills()
            Task { await store.refreshStatus() }
            store.say("Skill importiert: " + n)
        } else {
            store.say("Kein SKILL.md in diesem Ordner", bad: true)
        }
    }
}

// MARK: - Ersteinrichtung

struct SetupSheet: View {
    @ObservedObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var log = ""
    @State private var running = false
    @State private var setup = Backend.SetupState()

    var body: some View {
        SheetFrame(title: "WILLKOMMEN BEI JP CODING", width: 640, height: 560) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Einmalige Einrichtung. Trage deinen NVIDIA-NIM-Schluessel ein - "
                       + "den Rest installiert die App selbst.")
                        .font(Theme.f(11.5)).foregroundColor(Theme.muted).lineSpacing(4)

                    Text("NVIDIA NIM API-Schluessel").font(Theme.f(10.5))
                        .foregroundColor(Theme.muted).tracking(1)
                    SecureField("nvapi-...", text: $key)
                        .textFieldStyle(.plain).font(Theme.f(12))
                        .padding(.horizontal, 11).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.45))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke, lineWidth: 1)))
                    Link("Kostenlos bei build.nvidia.com holen",
                         destination: URL(string: "https://build.nvidia.com/settings/api-keys")!)
                        .font(Theme.f(10.5)).foregroundColor(Theme.green)

                    Divider().overlay(Theme.stroke2).padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 2) {
                        check("Claude Code CLI", setup.claude)
                        check("uv", setup.uv)
                        check("Proxy", setup.fcc)
                        check("Schluessel", setup.key)
                        check("Proxy laeuft", setup.proxy)
                    }

                    HStack(spacing: 8) {
                        Button(running ? "laeuft ..." : "Einrichten und starten") { go() }
                            .buttonStyle(JPButton(prominent: true)).disabled(running)
                        Button("Spaeter") { dismiss() }.buttonStyle(JPButton())
                    }

                    if !log.isEmpty {
                        ScrollView {
                            Text(log).font(Theme.f(10.5))
                                .foregroundColor(Color(red: 0.62, green: 0.85, blue: 0.74))
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        .frame(height: 180).padding(10)
                        .background(RoundedRectangle(cornerRadius: 9).fill(Color.black.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
                    }
                }
                .padding(18)
            }
        }
        .task { setup = await Backend.setupState() }
    }

    private func check(_ n: String, _ ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 10, weight: .bold))
                .foregroundColor(ok ? Theme.green : Theme.red).frame(width: 14)
            Text(n).font(Theme.f(11.5)).foregroundColor(Theme.text)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func go() {
        running = true; log = ""
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !k.isEmpty { Backend.envSet(["NVIDIA_NIM_API_KEY": k]); key = "" }
        Task {
            _ = await Backend.install { line in
                Task { @MainActor in
                    if line.hasPrefix("__DONE") { return }
                    log += line + "\n"
                }
            }
            setup = await Backend.setupState()
            await store.refreshStatus(); await store.refreshModels()
            running = false
            if setup.proxy && setup.key && setup.claude {
                store.say("Einrichtung fertig"); dismiss()
            } else {
                store.say("Noch nicht vollstaendig - siehe Liste", bad: true)
            }
        }
    }
}

// MARK: - Hilfe

struct HelpSheet: View {
    let commands: [SlashCmd]
    var body: some View {
        SheetFrame(title: "BEFEHLE", width: 700, height: 560) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group("In der App", commands.filter { $0.isApp })
                    group("An Claude Code weitergereicht", commands.filter { !$0.isApp })
                }
                .padding(18)
            }
        }
    }
    private func group(_ t: String, _ list: [SlashCmd]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(Theme.f(10.5)).foregroundColor(Theme.muted).tracking(1.2)
            ForEach(list) { c in
                HStack(alignment: .top, spacing: 10) {
                    Text("/" + c.name).font(Theme.f(12, .medium)).foregroundColor(Theme.green)
                        .frame(width: 190, alignment: .leading)
                    Text(c.desc).font(Theme.f(11)).foregroundColor(Theme.muted)
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
    }
}
