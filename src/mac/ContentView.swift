import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var store = Store()
    @StateObject var runner = Runner()
    @StateObject var probe = ModelProbe()
    @StateObject var pricing = Pricing()

    @State private var input = ""
    @State private var attachments: [String] = []
    @State private var liveText = ""
    @State private var liveTools: [ToolCall] = []
    @State private var liveMeta: String? = nil
    @State private var liveError: String? = nil
    @State private var liveIn = 0
    @State private var liveOut = 0
    @State private var liveCost: Double? = nil
    @State private var liveStart: Date? = nil
    @State private var liveTick = 0
    @State private var liveThinking = ""
    @State private var liveTodos: [TodoItem] = []
    @State private var showThinking = false
    @State private var fileIndex: [String] = []
    @State private var mentionIdx = 0
    @State private var streaming = false
    @State private var history: [String] = []
    @State private var historyIdx = 0

    @State private var slashIdx = 0
    @State private var showSettings = false
    @State private var showSkills = false
    @State private var showModels = false
    @State private var showSetup = false
    @State private var showHelp = false
    @State private var showUsage = false
    @State private var showSkillPicker = false
    @State private var rightPane: RightPane = .none
    @State private var editorFile: URL? = nil

    enum RightPane { case none, code, preview }

    private var chat: Chat? { store.chats.first { $0.id == store.currentID } }
    private var slashQuery: String? { Slash.query(in: input) }
    private var slashMatches: [SlashCmd] {
        guard let q = slashQuery else { return [] }
        return Array(Slash.filter(Slash.merged(cli: store.slashCommands), query: q).prefix(9))
    }
    private var popupOpen: Bool { !slashMatches.isEmpty || !mentionMatches.isEmpty }

    private var mentionQuery: String? { Slash.mention(in: input) }
    private var mentionMatches: [String] {
        guard let q = mentionQuery, slashMatches.isEmpty else { return [] }
        let low = q.lowercased()
        let hits = low.isEmpty ? fileIndex
                               : fileIndex.filter { $0.lowercased().contains(low) }
        return Array(hits.prefix(9))
    }

    /// Dateien des Arbeitsordners fuer @-Erwaehnungen, einmal je Chat eingelesen.
    private func buildFileIndex() {
        guard let root = chat?.cwd else { fileIndex = []; return }
        let skip: Set<String> = [".git", "node_modules", ".venv", "__pycache__",
                                 ".next", "dist", "build", ".cache", "Pods"]
        var out: [String] = []
        let base = URL(fileURLWithPath: root)
        if let en = FileManager.default.enumerator(at: base,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) {
            for case let u as URL in en {
                if skip.contains(u.lastPathComponent) { en.skipDescendants(); continue }
                let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir { continue }
                let rel = u.path.replacingOccurrences(of: base.path + "/", with: "")
                out.append(rel)
                if out.count >= 3000 { break }
            }
        }
        fileIndex = out.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count }
    }

    var body: some View {
        ZStack {
            BackdropView()
            HStack(spacing: 0) {
                sidebar.frame(width: 258)
                Divider().overlay(Theme.stroke2)
                mainPane
            }
        }
        .frame(minWidth: 1040, minHeight: 660)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) { toastView }
        .sheet(isPresented: $showSettings) { SettingsSheet(store: store) }
        .sheet(isPresented: $showSkills)   { SkillsSheet(store: store) }
        .sheet(isPresented: $showModels)   { ModelSheet(store: store, probe: probe, pricing: pricing, onPick: applyModel) }
        .sheet(isPresented: $showSetup)    { SetupSheet(store: store) }
        .sheet(isPresented: $showHelp)     { HelpSheet(commands: Slash.merged(cli: store.slashCommands)) }
        .sheet(isPresented: $showUsage)    { UsageSheet(store: store, pricing: pricing) }
        .sheet(isPresented: $showSkillPicker) {
            SkillPickerSheet { name in
                input = "Nutze den Skill \(name) fuer folgende Aufgabe: "
                store.say("Skill eingesetzt: " + name)
            }
        }
        .task {
            await store.refreshStatus()
            let s = await Backend.setupState()
            if !s.key || !s.claude || !s.fcc { showSetup = true }
            await store.refreshModels()
            if store.currentID == nil { store.currentID = store.chats.first?.id }
            // Beim ersten Start den Grundstock im Hintergrund pruefen,
            // damit die Modellliste sofort echte Zustaende zeigt.
            if probe.workingModels().isEmpty && !probe.sweepRunning {
                probe.sweep(store.curated, timeout: 90)
            }
            await pricing.refreshOpenRouter()
            buildFileIndex()
            startStatusLoop()
        }
    }

    // MARK: - Seitenleiste

    private var sidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("JP CODING")
                    .font(Theme.f(15, .bold)).foregroundColor(Theme.green)
                    .tracking(2.4).shadow(color: Theme.green.opacity(0.5), radius: 10)
                Text("LOCAL · NVIDIA NIM · ISOLIERT")
                    .font(Theme.f(9.5)).foregroundColor(Theme.muted).tracking(1.4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 13)

            Divider().overlay(Theme.stroke2)

            Button(action: newChat) {
                HStack(spacing: 7) { Image(systemName: "plus"); Text("NEUER CHAT") }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(JPButton(prominent: true))
            .padding(.horizontal, 12).padding(.vertical, 12)

            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(store.chats) { c in chatRow(c) }
                }
                .padding(.horizontal, 8)
            }

            Divider().overlay(Theme.stroke2)
            HStack(spacing: 6) {
                Button("Skills") { showSkills = true }.buttonStyle(JPButton())
                Button("Einstellungen") { showSettings = true }.buttonStyle(JPButton())
            }
            .padding(.horizontal, 10).padding(.vertical, 9)

            Divider().overlay(Theme.stroke2)
            VStack(spacing: 3) {
                statRow("Proxy", store.proxyOnline ? "online" : "offline", dot: store.proxyOnline)
                statRow("Skills aktiv", "\(store.skillCount)", dot: nil)
                statRow("Speicher", Paths.data.path.contains(".app/") ? "Paket" : "App Support", dot: nil)
                if let c = pricing.credits {
                    statRow("OpenRouter", String(format: "$%.4f verbraucht", c.usage), dot: nil)
                    if let rem = c.remaining {
                        statRow("Guthaben", String(format: "$%.2f frei", rem), dot: nil)
                    }
                }
                if chatCost > 0 {
                    statRow("dieser Chat", fmtCost(chatCost), dot: nil)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(Theme.glass)
    }

    private func statRow(_ l: String, _ r: String, dot: Bool?) -> some View {
        HStack(spacing: 6) {
            if let d = dot {
                Circle().fill(d ? Theme.green : Theme.red).frame(width: 7, height: 7)
                    .shadow(color: (d ? Theme.green : Theme.red).opacity(0.8), radius: 4)
            }
            Text(l).font(Theme.f(10.5)).foregroundColor(Theme.muted)
            Spacer()
            Text(r).font(Theme.f(10.5)).foregroundColor(Theme.muted)
        }
    }

    private func chatRow(_ c: Chat) -> some View {
        let on = c.id == store.currentID
        return HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(Theme.f(12)).foregroundColor(Theme.text).lineLimit(1)
                Text("\(URL(fileURLWithPath: c.cwd).lastPathComponent)  \(c.updated)")
                    .font(Theme.f(9.5)).foregroundColor(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { store.delete(c.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9))
            }
            .buttonStyle(.plain).foregroundColor(Theme.muted.opacity(0.7))
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(on ? Theme.green.opacity(0.13) : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(on ? Theme.green.opacity(0.3) : .clear, lineWidth: 1))
        )
        .contentShape(Rectangle())
        .onTapGesture { store.currentID = c.id; liveReset(); rebuildIndex() }
    }

    // MARK: - Hauptbereich

    private var mainPane: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke2)
            if rightPane == .none {
                chatColumn
            } else {
                HSplitView {
                    chatColumn.frame(minWidth: 380)
                    rightPaneView.frame(minWidth: 340)
                }
            }
        }
        .background(Theme.glass.opacity(0.5))
    }

    private var chatColumn: some View {
        VStack(spacing: 0) {
            transcript
            Divider().overlay(Theme.stroke2)
            composer
        }
    }

    @ViewBuilder private var rightPaneView: some View {
        if let c = chat {
            switch rightPane {
            case .code:    CodePane(root: c.cwd, selected: $editorFile)
            case .preview: PreviewPane(root: c.cwd)
            case .none:    EmptyView()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .font(.system(size: 24)).foregroundColor(Theme.muted.opacity(0.5))
                Text("Erst einen Chat mit Ordner anlegen")
                    .font(Theme.f(11)).foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { pickFolder() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder").font(.system(size: 10))
                    Text(chat.map { URL(fileURLWithPath: $0.cwd).lastPathComponent } ?? "—")
                        .lineLimit(1)
                }
                .frame(maxWidth: 170, alignment: .leading)
            }
            .buttonStyle(JPButton())
            .help(chat?.cwd ?? "Kein Chat")

            Button {
                showModels = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cpu").font(.system(size: 10))
                    Text(shortModel(chat?.model ?? store.state.model)).lineLimit(1)
                }
                .frame(maxWidth: 300, alignment: .leading)
            }
            .buttonStyle(JPButton(prominent: true))

            Button("TEST") { Task { await testModel() } }.buttonStyle(JPButton())

            Picker("", selection: Binding(
                get: { chat?.permission ?? store.state.permission },
                set: { setPermission($0) })) {
                Text("Vollzugriff").tag("bypassPermissions")
                Text("Nur Edits").tag("acceptEdits")
                Text("Planmodus").tag("plan")
                Text("Alles fragen").tag("default")
            }
            .labelsHidden().frame(width: 130)
            .font(Theme.f(11))

            Spacer()
            Button("CODE") { rightPane = (rightPane == .code) ? .none : .code }
                .buttonStyle(JPButton(prominent: rightPane == .code))
            Button("VORSCHAU") { rightPane = (rightPane == .preview) ? .none : .preview }
                .buttonStyle(JPButton(prominent: rightPane == .preview))
            Button("EXPORT") { exportChat() }.buttonStyle(JPButton())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private var transcript: some View {
        ScrollViewReader { sp in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let c = chat {
                        ForEach(c.messages) { m in MessageRow(message: m).id(m.id) }
                        if streaming || liveError != nil {
                            liveRow.id("LIVE")
                        }
                    } else {
                        emptyState.padding(.top, 120)
                    }
                    Color.clear.frame(height: 8).id("BOTTOM")
                }
                .padding(.horizontal, 26).padding(.vertical, 22)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: liveText) { _, _ in sp.scrollTo("BOTTOM", anchor: .bottom) }
            .onChange(of: liveTick) { _, _ in }
            .onChange(of: chat?.messages.count ?? 0) { _, _ in sp.scrollTo("BOTTOM", anchor: .bottom) }
        }
    }

    private var liveRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text("JP").font(Theme.f(10)).foregroundColor(Theme.green).tracking(1.6)
                if streaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).scaleEffect(0.5).frame(width: 14, height: 10)
                        Text(workingLabel).font(Theme.f(10)).foregroundColor(Theme.muted)
                    }
                }
            }
            if !liveText.isEmpty {
                MDBody(text: liveText)
            } else if streaming {
                HStack(spacing: 5) {
                    Rectangle().fill(Theme.green).frame(width: 8, height: 15)
                        .shadow(color: Theme.green, radius: 5)
                }
            }
            if !liveThinking.isEmpty {
                DisclosureGroup(isExpanded: $showThinking) {
                    Text(liveThinking).font(Theme.f(11))
                        .foregroundColor(Theme.muted).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Text("Denkschritte (\(liveThinking.count / 4) Token)")
                        .font(Theme.f(10)).foregroundColor(Theme.muted)
                }
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.02))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
            }
            if !liveTools.isEmpty { ToolChips(tools: liveTools) }
            if let e = liveError { ErrorBox(text: e) }
            if let m = liveMeta {
                Text(m).font(Theme.f(10)).foregroundColor(Theme.muted.opacity(0.8))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 15) {
            Text("JP CODING")
                .font(Theme.f(32, .bold)).foregroundColor(Theme.green).tracking(7)
                .shadow(color: Theme.green.opacity(0.4), radius: 22)
            Text("Kein Chat geoeffnet.\nStarte mit  + NEUER CHAT  oder tippe  /new")
                .font(Theme.f(12)).foregroundColor(Theme.muted)
                .multilineTextAlignment(.center).lineSpacing(6)
            Text("Laeuft ueber deinen lokalen NVIDIA-NIM-Proxy.\nVollstaendig getrennt vom echten Claude.")
                .font(Theme.f(11)).foregroundColor(Theme.muted.opacity(0.65))
                .multilineTextAlignment(.center).lineSpacing(5)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Eingabe

    /// Aufgabenliste, die der Agent selbst fuehrt - wie im echten Claude Code.
    @ViewBuilder private var todoStrip: some View {
        if !liveTodos.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("AUFGABEN").font(Theme.f(9)).foregroundColor(Theme.muted).tracking(1.2)
                    Text("\(liveTodos.filter { $0.status == "completed" }.count)/\(liveTodos.count)")
                        .font(Theme.f(9)).foregroundColor(Theme.green)
                    Spacer()
                }
                ForEach(liveTodos) { t in
                    HStack(spacing: 7) {
                        Image(systemName: t.symbol).font(.system(size: 9))
                            .foregroundColor(t.status == "completed" ? Theme.green
                                             : (t.status == "in_progress" ? Theme.warn : Theme.muted))
                        Text(t.status == "in_progress" && !t.active.isEmpty ? t.active : t.text)
                            .font(Theme.f(10.5))
                            .foregroundColor(t.status == "completed" ? Theme.muted : Theme.text)
                            .strikethrough(t.status == "completed", color: Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.glass2)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.stroke2, lineWidth: 1)))
            .padding(.bottom, 6)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 7) {
            todoStrip
            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(attachments.enumerated()), id: \.offset) { i, f in
                            HStack(spacing: 5) {
                                Image(systemName: "doc").font(.system(size: 9))
                                Text(URL(fileURLWithPath: f).lastPathComponent).font(Theme.f(11))
                                Button { attachments.remove(at: i) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }.buttonStyle(.plain)
                            }
                            .foregroundColor(Theme.green)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.green.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.stroke, lineWidth: 1)))
                        }
                    }
                }
                .frame(height: 26)
            }

            HStack(alignment: .bottom, spacing: 9) {
                Button { pickFiles() } label: { Image(systemName: "paperclip").font(.system(size: 13)) }
                    .buttonStyle(.plain).foregroundColor(Theme.muted)
                    .frame(width: 26, height: 26)

                ComposerTextView(
                    text: $input, popupOpen: popupOpen,
                    onSubmit: { submit() },
                    onMove: { d in
                        if !mentionMatches.isEmpty {
                            mentionIdx = max(0, min(mentionMatches.count - 1, mentionIdx + d))
                        } else if !slashMatches.isEmpty {
                            slashIdx = max(0, min(slashMatches.count - 1, slashIdx + d))
                        }
                    },
                    onComplete: {
                        if !mentionMatches.isEmpty { completeMention() } else { completeSlash() }
                    },
                    onEscape: { input = "" },
                    onHistory: { _ in
                        if historyIdx > 0 { historyIdx -= 1; input = history[historyIdx] }
                        else if let last = history.last { input = last }
                    })
                .frame(height: inputHeight)

                if streaming {
                    Button { runner.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)) }
                        .buttonStyle(JPButton(danger: true))
                } else {
                    Button { submit() } label: { Image(systemName: "arrow.up").font(.system(size: 12)) }
                        .buttonStyle(JPButton(prominent: true))
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8)
            .glass(12, fill: Theme.glass2)
            .overlay(alignment: .topLeading) {
                if popupOpen {
                    slashPopup.offset(y: -CGFloat(max(slashMatches.count, mentionMatches.count)) * 30 - 14)
                }
            }

            statusBar
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
    }

    /// Dauerhafte Statuszeile ganz unten, wie in der Claude-App.
    private var statusBar: some View {
        HStack(spacing: 0) {
            Circle().fill(store.proxyOnline ? Theme.green : Theme.red)
                .frame(width: 6, height: 6)
                .shadow(color: (store.proxyOnline ? Theme.green : Theme.red).opacity(0.7), radius: 3)
            Text(shortModel(chat?.model ?? store.state.model))
                .foregroundColor(Theme.muted).lineLimit(1).padding(.leading, 6)

            sep
            Image(systemName: "folder").font(.system(size: 8)).foregroundColor(Theme.muted.opacity(0.7))
            Text(chat.map { URL(fileURLWithPath: $0.cwd).lastPathComponent } ?? "—")
                .foregroundColor(Theme.muted).lineLimit(1).padding(.leading, 4)

            sep
            Text(permLabel).foregroundColor(Theme.muted)

            Spacer(minLength: 10)

            if streaming {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small).scaleEffect(0.42).frame(width: 12, height: 9)
                    Text(workingLabel).foregroundColor(Theme.green.opacity(0.9)).lineLimit(1)
                }
            } else if let last = chat?.messages.last, last.role == "assistant",
                      let inTok = last.inputTokens {
                Text("\(fmtTokens(inTok)) ein · \(fmtTokens(last.outputTokens ?? 0)) aus")
                    .foregroundColor(Theme.muted)
            } else {
                Text("bereit").foregroundColor(Theme.muted.opacity(0.7))
            }

            if chatCost > 0 {
                sep
                Text("Chat " + fmtCost(chatCost)).foregroundColor(Theme.green.opacity(0.9))
            }
            if let c = pricing.credits {
                sep
                Button { showUsage = true } label: {
                    Text(c.remaining != nil
                         ? String(format: "$%.2f frei", c.remaining!)
                         : String(format: "$%.4f verbraucht", c.usage))
                        .foregroundColor(Theme.muted)
                }
                .buttonStyle(.plain)
                .help("Nutzung anzeigen")
            }
        }
        .font(Theme.f(9.5))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.glass2)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke2, lineWidth: 1)))
        .padding(.top, 7)
    }

    private var sep: some View {
        Text("│").foregroundColor(Theme.muted.opacity(0.3)).padding(.horizontal, 7)
    }

    private var permLabel: String {
        switch chat?.permission ?? store.state.permission {
        case "bypassPermissions": return "Vollzugriff"
        case "acceptEdits":       return "nur Edits"
        case "plan":              return "Planmodus"
        default:                  return "fragt nach"
        }
    }

    private var inputHeight: CGFloat {
        let lines = max(1, min(8, input.components(separatedBy: "\n").count))
        return CGFloat(lines) * 18 + 12
    }

    @ViewBuilder private var slashPopup: some View {
        if !mentionMatches.isEmpty { mentionPopup } else { commandPopup }
    }

    private var mentionPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(mentionMatches.enumerated()), id: \.element) { i, f in
                HStack(spacing: 9) {
                    Image(systemName: "doc").font(.system(size: 9))
                        .foregroundColor(i == mentionIdx ? Theme.green : Theme.muted)
                    Text(f).font(Theme.f(11.5))
                        .foregroundColor(i == mentionIdx ? Theme.green : Theme.text)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(i == mentionIdx ? Theme.green.opacity(0.12) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { mentionIdx = i; completeMention() }
            }
        }
        .frame(width: 520)
        .glass(11, fill: Theme.panel.opacity(0.98))
        .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
    }

    private func completeMention() {
        guard mentionIdx < mentionMatches.count, let at = input.lastIndex(of: "@") else { return }
        input = String(input[input.startIndex..<at]) + "@" + mentionMatches[mentionIdx] + " "
        mentionIdx = 0
    }

    private var commandPopup: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(slashMatches.enumerated()), id: \.element.id) { i, c in
                HStack(spacing: 9) {
                    Text("/" + c.name).font(Theme.f(12, .medium))
                        .foregroundColor(i == slashIdx ? Theme.green : Theme.text)
                        .frame(width: 160, alignment: .leading)
                    Text(c.desc).font(Theme.f(10.5)).foregroundColor(Theme.muted).lineLimit(1)
                    Spacer()
                    if !c.isApp {
                        Text("CLI").font(Theme.f(9)).foregroundColor(Theme.muted.opacity(0.7))
                    }
                }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(i == slashIdx ? Theme.green.opacity(0.12) : .clear)
                .contentShape(Rectangle())
                .onTapGesture { slashIdx = i; completeSlash() }
            }
        }
        .frame(width: 520)
        .glass(11, fill: Theme.panel.opacity(0.98))
        .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
    }

    // MARK: - Aktionen

    private func startStatusLoop() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await store.refreshStatus()
                await pricing.refreshCredits()
            }
        }
    }

    private func rebuildIndex() { buildFileIndex() }

    private func liveReset() {
        liveText = ""; liveTools = []; liveMeta = nil; liveError = nil
        liveIn = 0; liveOut = 0; liveCost = nil; liveStart = nil
        liveThinking = ""; liveTodos = []
    }

    private func shortModel(_ m: String) -> String { Store.shortModel(m) }

    private func fmtTokens(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fk", Double(n)/1000) : "\(n)"
    }
    private func fmtCost(_ c: Double) -> String {
        c < 0.01 ? String(format: "$%.4f", c) : String(format: "$%.3f", c)
    }
    /// Summe der Kosten dieses Chats.
    /// Was gerade passiert: Zeit, letzter Werkzeugaufruf, empfangene Zeichen.
    private var workingLabel: String {
        var bits: [String] = []
        if let st = liveStart {
            bits.append(String(format: "%.0fs", Date().timeIntervalSince(st)))
        }
        if let last = liveTools.last {
            bits.append("nutzt " + last.name)
        } else if liveText.isEmpty {
            bits.append("denkt nach")
        } else {
            bits.append("schreibt")
        }
        if !liveText.isEmpty {
            let approx = max(1, liveText.count / 4)
            bits.append("~\(approx) Token")
        }
        return bits.joined(separator: " · ")
    }

    private var chatCost: Double {
        (chat?.messages ?? []).compactMap { $0.costUSD }.reduce(0, +)
    }

    private func completeSlash() {
        guard slashIdx < slashMatches.count else { return }
        let c = slashMatches[slashIdx]
        if c.isApp { input = ""; slashIdx = 0; runApp(command: c.name) }
        else { input = "/" + c.name + " "; slashIdx = 0 }
    }

    private func runApp(command: String) {
        switch command {
        case "new":         newChat()
        case "folder":      pickFolder()
        case "model":       showModels = true
        case "test":        Task { await testModel() }
        case "attach":      pickFiles()
        case "skills":      showSkills = true
        case "settings":    showSettings = true
        case "export":      exportChat()
        case "stop":        runner.stop()
        case "help":        showHelp = true
        case "skill":       showSkillPicker = true
        case "usage":       showUsage = true
        case "code":        rightPane = (rightPane == .code) ? .none : .code
        case "preview":     rightPane = (rightPane == .preview) ? .none : .preview
        case "clear":       clearChat()
        case "proxy":       Task {
                                store.say("Proxy startet neu ...")
                                let ok = await Backend.restartProxy()
                                await store.refreshStatus()
                                store.say(ok ? "Proxy laeuft" : "Proxy nicht erreichbar", bad: !ok)
                            }
        case "permissions":
            let order = ["bypassPermissions", "acceptEdits", "plan", "default"]
            let cur = chat?.permission ?? store.state.permission
            let next = order[((order.firstIndex(of: cur) ?? 0) + 1) % order.count]
            setPermission(next)
            store.say("Berechtigungen: " + next)
        default: break
        }
    }

    private func newChat() {
        guard let dir = chooseFolder(title: "Ordner fuer diesen Chat") else { return }
        if dir == Paths.home.path { store.say("Home-Verzeichnis nicht erlaubt", bad: true); return }
        _ = store.newChat(cwd: dir)
        liveReset(); rebuildIndex()
        store.say("Chat angelegt: " + URL(fileURLWithPath: dir).lastPathComponent)
    }

    private func pickFolder() {
        guard var c = chat else { newChat(); return }
        guard let dir = chooseFolder(title: "Arbeitsordner waehlen") else { return }
        c.cwd = dir; store.save(c)
        store.state.lastDir = dir; store.saveState()
        store.say("Ordner: " + URL(fileURLWithPath: dir).lastPathComponent)
    }

    private func chooseFolder(title: String) -> String? {
        let p = NSOpenPanel()
        p.message = title
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.allowsMultipleSelection = false; p.canCreateDirectories = true
        p.directoryURL = URL(fileURLWithPath: store.state.lastDir)
        return p.runModal() == .OK ? p.url?.path : nil
    }

    private func pickFiles() {
        let p = NSOpenPanel()
        p.message = "Dateien anhaengen"
        p.canChooseDirectories = false; p.canChooseFiles = true
        p.allowsMultipleSelection = true
        p.directoryURL = URL(fileURLWithPath: chat?.cwd ?? store.state.lastDir)
        if p.runModal() == .OK {
            for u in p.urls where !attachments.contains(u.path) { attachments.append(u.path) }
        }
    }

    private func applyModel(_ m: String) {
        Log.w("applyModel \(m)")
        setModel(m)
        store.say("Modell: " + shortModel(m) + " - pruefe ...")
        Task {
            let r = await probe.test(m)
            if r.ok {
                store.say("Modell aktiv: " + shortModel(m)
                          + String(format: " (%.1fs)", Double(r.ms) / 1000))
                return
            }
            store.say(shortModel(m) + " antwortet nicht - suche Ersatz ...", bad: true)
            if let alt = await findWorking(excluding: m) {
                setModel(alt)
                store.say("automatisch gewechselt auf " + shortModel(alt))
            } else {
                store.say("Kein funktionierendes Modell gefunden. Schluessel oder NVIDIA-Limit pruefen.", bad: true)
            }
        }
    }

    private func setModel(_ m: String) {
        store.state.model = m; store.saveState()
        if var c = chat {
            let hadSession = c.sessionId != nil && c.sessionModel != nil && c.sessionModel != m
            c.model = m; store.save(c)
            if hadSession {
                store.say("Neue Sitzung mit " + shortModel(m) + " - Verlauf wird mitgegeben")
            }
        }
    }

    /// Erst bekannte Treffer, dann der Grundstock der Reihe nach.
    private func findWorking(excluding bad: String) async -> String? {
        for m in probe.workingModels() where m != bad { return m }
        for m in store.curated where m != bad {
            if await probe.test(m).ok { return m }
        }
        return nil
    }

    private func setPermission(_ p: String) {
        store.state.permission = p; store.saveState()
        if var c = chat { c.permission = p; store.save(c) }
    }

    private func testModel() async {
        let m = chat?.model ?? store.state.model
        store.say("Teste " + shortModel(m) + " ...")
        let (ok, detail) = await Backend.testModel(m)
        if ok { store.say("antwortet: " + detail); return }
        store.say("faellt aus: " + detail + " - suche Ersatz", bad: true)
        let r = await Backend.repairModel(current: m)
        if r.changed { applyModel(r.model); store.say("gewechselt auf " + shortModel(r.model)) }
        else if r.broken { store.say("Kein Modell erreichbar - Schluessel oder Limit pruefen", bad: true) }
    }

    private func clearChat() {
        guard var c = chat else { return }
        c.messages = []; c.sessionId = nil; c.title = "Neuer Chat"
        store.save(c); liveReset()
        store.say("Verlauf geleert, neue Sitzung")
    }

    private func exportChat() {
        guard let c = chat else { store.say("Kein Chat geoeffnet", bad: true); return }
        var lines = ["# \(c.title)", "", "Ordner: `\(c.cwd)`", "Modell: `\(c.model)`",
                     "Erstellt: \(c.created)", "", "---", ""]
        for m in c.messages {
            lines.append("### \(m.role == "user" ? "Du" : "JP Coding")  ·  \(m.ts)")
            lines.append("")
            if !m.files.isEmpty { lines.append("Anhaenge: " + m.files.joined(separator: ", ")); lines.append("") }
            lines.append(m.text)
            if !m.tools.isEmpty { lines.append(""); lines.append("_Tools: " + m.tools.map { $0.name }.joined(separator: ", ") + "_") }
            lines.append("")
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = c.title.replacingOccurrences(of: "/", with: "-").prefix(40) + ".md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let u = panel.url {
            try? lines.joined(separator: "\n").write(to: u, atomically: true, encoding: .utf8)
            store.say("Exportiert")
        }
    }

    private func submit() {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty || !attachments.isEmpty else { return }
        guard !streaming else { return }

        // App-Befehl direkt ausfuehren
        if raw.hasPrefix("/") {
            let name = String(raw.dropFirst()).components(separatedBy: " ").first ?? ""
            if Slash.app.contains(where: { $0.name == name }) {
                input = ""; runApp(command: name); return
            }
        }
        guard var c = chat else { store.say("Erst einen Chat anlegen (/new)", bad: true); return }

        let files = attachments
        var prompt = raw
        if !files.isEmpty {
            prompt = "Angehaengte Dateien (lies sie bei Bedarf mit dem Read-Tool):\n"
                   + files.map { "- " + $0 }.joined(separator: "\n") + "\n\n" + raw
        }

        // Gedaechtnis: laesst sich die Sitzung nicht fortsetzen (erste Nachricht
        // oder Modellwechsel), bekommt das Modell den Verlauf als Kontext mit.
        let canResume = (c.sessionId?.isEmpty == false) && (c.sessionModel == c.model)
        if !canResume && !c.messages.isEmpty {
            prompt = Store.transcript(c) + "\n" + prompt
            Log.w("kein resume moeglich - Verlauf mit \(c.messages.count) Nachrichten mitgegeben")
        }

        history.append(raw); historyIdx = history.count
        c.messages.append(Message(role: "user", text: raw, files: files))
        if c.title == "Neuer Chat" {
            c.title = String((raw.isEmpty ? URL(fileURLWithPath: files.first ?? "Chat").lastPathComponent : raw).prefix(46))
        }
        store.save(c)
        input = ""; attachments = []; liveReset(); streaming = true

        liveStart = Date()
        Task {
            while streaming {
                try? await Task.sleep(nanoseconds: 900_000_000)
                liveTick &+= 1
            }
        }
        Task {
            if !(await Backend.ensureProxy(wait: 20)) {
                liveError = "Proxy nicht erreichbar. /proxy oder Einstellungen > System."
                streaming = false; return
            }
            runner.run(chat: c, prompt: prompt, onEvent: handle, onFinish: finish)
            startWatchdog(model: c.model)
        }
    }

    /// Meldet, wenn nach 45s noch nichts vom Modell kam - sonst haengt die App stumm.
    private func startWatchdog(model: String) {
        Task {
            try? await Task.sleep(nanoseconds: 90_000_000_000)
            guard streaming, liveText.isEmpty, liveTools.isEmpty, liveError == nil else { return }
            liveError = "Das Modell \(shortModel(model)) hat nach 90 Sekunden nichts geliefert.\n"
                      + "Wahrscheinlich ist es bei NVIDIA gerade nicht verfuegbar.\n"
                      + "Druecke TEST - die App sucht dann automatisch ein funktionierendes Modell."
        }
    }

    private func handle(_ e: RunEvent) {
        switch e {
        case .initialized(_, _, let sid, let slash):
            if !slash.isEmpty { store.slashCommands = slash }
            if var c = chat, let sid, !sid.isEmpty {
                if c.sessionId != sid || c.sessionModel != c.model {
                    c.sessionId = sid
                    c.sessionModel = c.model
                    store.save(c)
                    Log.w("session gemerkt: \(sid) modell=\(c.model)")
                }
            }
        case .text(let t): liveText += t
        case .thinking(let t): liveThinking += t
        case .todos(let items): liveTodos = items
        case .tool(let n, let i): liveTools.append(ToolCall(name: n, input: i))
        case .toolResult(let r):
            if var last = liveTools.popLast() { last.result = r; liveTools.append(last) }
        case .done(let ms, let turns, _, let input, let output):
            liveIn = input; liveOut = output
            let mdl = chat?.model ?? store.state.model
            if let inf = pricing.info(for: mdl), !inf.isFree {
                liveCost = inf.cost(input: input, output: output)
            }
            var parts: [String] = []
            if let ms { parts.append(String(format: "%.1fs", Double(ms)/1000.0)) }
            parts.append("\(turns ?? 1) Schritt(e)")
            if input > 0 { parts.append("\(fmtTokens(input)) ein / \(fmtTokens(output)) aus") }
            if let c = liveCost { parts.append(fmtCost(c)) }
            liveMeta = parts.joined(separator: " · ")
        case .failure(let m): liveError = m
        }
    }

    private func finish() {
        streaming = false
        guard var c = chat else { return }
        var m = Message(role: "assistant", text: liveText, tools: liveTools)
        m.isError = liveError != nil
        if liveIn > 0 { m.inputTokens = liveIn; m.outputTokens = liveOut }
        if !liveThinking.isEmpty { m.thinking = liveThinking }
        m.costUSD = liveCost
        if let e = liveError, liveText.isEmpty { m.text = e }
        if liveText.isEmpty && liveTools.isEmpty && liveError == nil {
            m.isError = true
            m.text = "Keine Antwort vom Modell \(shortModel(c.model)). "
                   + "Druecke TEST, um auf ein funktionierendes Modell zu wechseln."
        }
        c.messages.append(m)
        store.save(c)
        liveReset()
    }

    private var toastView: some View {
        Group {
            if let t = store.toast {
                Text(t).font(Theme.f(12))
                    .foregroundColor(store.toastBad ? Theme.red : Theme.text)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glass(11, fill: Theme.panel.opacity(0.96))
                    .padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.toast)
    }
}

// MARK: - Bausteine

struct MessageRow: View {
    let message: Message
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(message.role == "user" ? "DU" : "JP")
                    .font(Theme.f(10)).foregroundColor(Theme.green).tracking(1.6)
                Text(message.ts).font(Theme.f(10)).foregroundColor(Theme.muted)
            }
            if !message.files.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.files, id: \.self) { f in
                        HStack(spacing: 4) {
                            Image(systemName: "doc").font(.system(size: 9))
                            Text(URL(fileURLWithPath: f).lastPathComponent).font(Theme.f(10.5))
                        }
                        .foregroundColor(Theme.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.green.opacity(0.1)))
                    }
                }
            }
            if message.role == "user" {
                Text(message.text)
                    .font(Theme.f(13)).foregroundColor(Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .glass(11, fill: Theme.glass2)
            } else if message.isError {
                ErrorBox(text: message.text)
            } else {
                MDBody(text: message.text)
            }
            if !message.tools.isEmpty { ToolChips(tools: message.tools) }
            if let inTok = message.inputTokens {
                let out = message.outputTokens ?? 0
                let cost = message.costUSD
                Text("\(inTok >= 1000 ? String(format: "%.1fk", Double(inTok)/1000) : "\(inTok)") ein / "
                   + "\(out >= 1000 ? String(format: "%.1fk", Double(out)/1000) : "\(out)") aus"
                   + (cost != nil ? String(format: "  ·  $%.4f", cost!) : ""))
                    .font(Theme.f(10)).foregroundColor(Theme.muted.opacity(0.8))
            }
        }
    }
}

struct MDBody: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Markdown.parse(text)) { b in
                switch b {
                case .heading(let l, let s):
                    Text(s).font(Theme.f(l == 1 ? 15 : 14, .semibold))
                        .foregroundColor(Theme.green).padding(.top, 3)
                case .paragraph(let s):
                    Text(Markdown.inline(s)).font(Theme.f(13)).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let lang, let body):
                    CodeBlock(lang: lang, code: body)
                case .bullets(let items):
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(items, id: \.self) { it in
                            HStack(alignment: .top, spacing: 7) {
                                Text("·").foregroundColor(Theme.green).font(Theme.f(13))
                                Text(Markdown.inline(it)).font(Theme.f(13))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                case .numbered(let items):
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                            HStack(alignment: .top, spacing: 7) {
                                Text("\(i+1).").foregroundColor(Theme.green).font(Theme.f(12.5))
                                Text(Markdown.inline(it)).font(Theme.f(13))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodeBlock: View {
    let lang: String, code: String
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.isEmpty ? "code" : lang).font(Theme.f(9.5)).foregroundColor(Theme.muted)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_400_000_000); copied = false }
                } label: {
                    Text(copied ? "kopiert" : "kopieren").font(Theme.f(9.5))
                }
                .buttonStyle(.plain).foregroundColor(copied ? Theme.green : Theme.muted)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code).font(Theme.f(12)).foregroundColor(Color(red: 0.75, green: 0.96, blue: 0.85))
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.bottom, 11)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke, lineWidth: 1)))
    }
}

struct ToolChips: View {
    let tools: [ToolCall]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tools) { t in
                HStack(spacing: 8) {
                    Text(t.name).font(Theme.f(10.5, .medium)).foregroundColor(Theme.green)
                    Text(t.input).font(Theme.f(10)).foregroundColor(Theme.muted).lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.green.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.stroke2, lineWidth: 1)))
                .help(t.result ?? t.input)
            }
        }
    }
}

struct ErrorBox: View {
    let text: String
    var body: some View {
        Text(text).font(Theme.f(12)).foregroundColor(Theme.red)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.red.opacity(0.09))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.red.opacity(0.3), lineWidth: 1)))
    }
}
