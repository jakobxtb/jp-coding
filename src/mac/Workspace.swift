import SwiftUI
import AppKit
import WebKit

// MARK: - Dateibaum

final class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let isDir: Bool
    @Published var children: [FileNode]? = nil
    init(url: URL, isDir: Bool) { self.url = url; self.isDir = isDir }

    static let skip: Set<String> = [".git", "node_modules", ".DS_Store", ".venv", "__pycache__",
                                    ".next", "dist", "build", ".cache"]

    func loadChildren() {
        guard isDir, children == nil else { return }
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: url,
            includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        children = items
            .filter { !FileNode.skip.contains($0.lastPathComponent) }
            .map { u in
                let d = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return FileNode(url: u, isDir: d)
            }
            .sorted { a, b in
                if a.isDir != b.isDir { return a.isDir }
                return a.url.lastPathComponent.lowercased() < b.url.lastPathComponent.lowercased()
            }
    }
    func reload() { children = nil; loadChildren() }
}

struct FileTreeRow: View {
    @ObservedObject var node: FileNode
    @Binding var selected: URL?
    var depth: Int = 0
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if node.isDir {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8)).foregroundColor(Theme.muted).frame(width: 10)
                } else {
                    Spacer().frame(width: 10)
                }
                Image(systemName: node.isDir ? "folder" : icon(for: node.url))
                    .font(.system(size: 9))
                    .foregroundColor(node.isDir ? Theme.muted : Theme.green.opacity(0.8))
                Text(node.url.lastPathComponent)
                    .font(Theme.f(11)).lineLimit(1)
                    .foregroundColor(selected == node.url ? Theme.green : Theme.text)
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(depth) * 11 + 6)
            .padding(.vertical, 3).padding(.trailing, 6)
            .background(selected == node.url ? Theme.green.opacity(0.12) : .clear)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDir { node.loadChildren(); open.toggle() }
                else { selected = node.url }
            }

            if open, let kids = node.children {
                ForEach(kids) { k in
                    FileTreeRow(node: k, selected: $selected, depth: depth + 1)
                }
            }
        }
    }

    private func icon(for u: URL) -> String {
        switch u.pathExtension.lowercased() {
        case "swift", "py", "js", "ts", "tsx", "jsx", "go", "rs", "rb", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        case "json", "yml", "yaml", "toml": return "curlybraces"
        case "md", "txt": return "doc.text"
        case "png", "jpg", "jpeg", "gif", "svg", "webp": return "photo"
        default: return "doc"
        }
    }
}

// MARK: - Code-Editor

struct CodePane: View {
    let root: String
    @Binding var selected: URL?
    @StateObject private var tree: FileNodeHolder
    @State private var text = ""
    @State private var loaded: URL? = nil
    @State private var dirty = false
    @State private var note: String? = nil
    @State private var openTabs: [URL] = []

    init(root: String, selected: Binding<URL?>) {
        self.root = root
        self._selected = selected
        _tree = StateObject(wrappedValue: FileNodeHolder(root: root))
    }

    final class FileNodeHolder: ObservableObject {
        @Published var node: FileNode
        init(root: String) {
            let u = URL(fileURLWithPath: root)
            node = FileNode(url: u, isDir: true)
            node.loadChildren()
        }
        func rebuild(root: String) {
            let u = URL(fileURLWithPath: root)
            let n = FileNode(url: u, isDir: true); n.loadChildren()
            node = n
        }
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("DATEIEN").font(Theme.f(9.5)).foregroundColor(Theme.muted).tracking(1.4)
                    Spacer()
                    Button { tree.rebuild(root: root) } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 9))
                    }.buttonStyle(.plain).foregroundColor(Theme.muted)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                Divider().overlay(Theme.stroke2)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let kids = tree.node.children {
                            ForEach(kids) { k in FileTreeRow(node: k, selected: $selected) }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minWidth: 170, idealWidth: 220, maxWidth: 320)
            .background(Theme.glass2)

            VStack(spacing: 0) {
                // Tab-Leiste
                HStack(spacing: 3) {
                    ForEach(openTabs.suffix(6), id: \.self) { u in
                        HStack(spacing: 5) {
                            Text(u.lastPathComponent).font(Theme.f(10.5))
                                .foregroundColor(selected == u ? Theme.green : Theme.muted)
                                .lineLimit(1)
                            if selected == u && dirty {
                                Circle().fill(Theme.warn).frame(width: 5, height: 5)
                            }
                            Button {
                                openTabs.removeAll { $0 == u }
                                if selected == u { selected = openTabs.last }
                            } label: { Image(systemName: "xmark").font(.system(size: 7)) }
                                .buttonStyle(.plain).foregroundColor(Theme.muted.opacity(0.7))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(selected == u ? Theme.green.opacity(0.12) : Color.clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selected = u }
                    }
                    Spacer(minLength: 4)
                    if let n = note {
                        Text(n).font(Theme.f(9.5)).foregroundColor(Theme.green)
                    }
                    Button("Sichern") { save() }.buttonStyle(JPButton(prominent: dirty))
                        .disabled(selected == nil || !dirty)
                }
                .padding(.horizontal, 8)
                .frame(height: 34)
                .background(Theme.glass2)
                Divider().overlay(Theme.stroke2)

                if selected == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text").font(.system(size: 26)).foregroundColor(Theme.muted.opacity(0.5))
                        Text("Datei links auswaehlen").font(Theme.f(11)).foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isImage(selected!) {
                    imageView(selected!)
                } else {
                    SyntaxTextView(text: $text,
                                   language: Syntax.language(for: selected),
                                   onChange: { dirty = true },
                                   onSave: { save() })
                }
            }
            .frame(minWidth: 300)
        }
        .onChange(of: selected) { _, u in
            if let u, !openTabs.contains(u) { openTabs.append(u) }
            if openTabs.count > 12 { openTabs.removeFirst(openTabs.count - 12) }
            load(force: true)
        }
        .onAppear { load(force: true) }
        .onChange(of: root) { _, r in tree.rebuild(root: r); selected = nil }
    }

    private func isImage(_ u: URL) -> Bool {
        ["png","jpg","jpeg","gif","webp","bmp","tiff"].contains(u.pathExtension.lowercased())
    }

    private func imageView(_ u: URL) -> some View {
        Group {
            if let img = NSImage(contentsOf: u) {
                ScrollView([.horizontal, .vertical]) {
                    Image(nsImage: img).resizable().scaledToFit()
                        .frame(maxWidth: 900).padding()
                }
            } else {
                Text("Bild konnte nicht geladen werden")
                    .font(Theme.f(11)).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func load(force: Bool) {
        guard let u = selected else { text = ""; loaded = nil; dirty = false; return }
        if !force && loaded == u { return }
        if isImage(u) { loaded = u; dirty = false; return }
        if let s = try? String(contentsOf: u, encoding: .utf8) {
            text = s; loaded = u; dirty = false; flash("geladen")
        } else {
            text = "(Binaerdatei oder nicht lesbar)"; loaded = u; dirty = false
        }
    }

    private func save() {
        guard let u = selected else { return }
        do { try text.write(to: u, atomically: true, encoding: .utf8); dirty = false; flash("gesichert") }
        catch { flash("Fehler: \(error.localizedDescription)") }
    }

    private func flash(_ s: String) {
        note = s
        Task { try? await Task.sleep(nanoseconds: 1_600_000_000); if note == s { note = nil } }
    }
}

// MARK: - Live-Vorschau

struct PreviewPane: View {
    let root: String
    @State private var target: URL? = nil
    @State private var autoReload = true
    @State private var lastStamp: Date? = nil
    @State private var reloadTick = 0
    @State private var urlText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("VORSCHAU").font(Theme.f(9.5)).foregroundColor(Theme.muted).tracking(1.4)
                TextField("index.html oder http://localhost:3000", text: $urlText)
                    .textFieldStyle(.plain).font(Theme.f(11))
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.4))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.stroke2, lineWidth: 1)))
                    .onSubmit { applyURL() }
                Button("Oeffnen") { applyURL() }.buttonStyle(JPButton())
                Button { reloadTick += 1 } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(JPButton())
                Toggle("auto", isOn: $autoReload)
                    .toggleStyle(.checkbox).font(Theme.f(10)).foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            Divider().overlay(Theme.stroke2)

            if let t = target {
                WebView(url: t, reloadToken: reloadTick)
            } else {
                VStack(spacing: 9) {
                    Image(systemName: "globe").font(.system(size: 26)).foregroundColor(Theme.muted.opacity(0.5))
                    Text("Keine Vorschau geladen").font(Theme.f(11)).foregroundColor(Theme.muted)
                    Text("Trage eine Datei aus dem Projektordner ein (z.B. index.html)\noder eine Adresse wie http://localhost:3000")
                        .font(Theme.f(10)).foregroundColor(Theme.muted.opacity(0.7))
                        .multilineTextAlignment(.center).lineSpacing(4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { autoDetect() }
        .onChange(of: root) { _, _ in target = nil; urlText = ""; autoDetect() }
        .task(id: autoReload) { await watchLoop() }
    }

    private func autoDetect() {
        for name in ["index.html", "public/index.html", "dist/index.html", "build/index.html"] {
            let u = URL(fileURLWithPath: root).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: u.path) {
                target = u; urlText = name; stamp(); return
            }
        }
    }

    private func applyURL() {
        let t = urlText.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { target = nil; return }
        if t.hasPrefix("http://") || t.hasPrefix("https://") {
            target = URL(string: t)
        } else {
            let u = t.hasPrefix("/") ? URL(fileURLWithPath: t)
                                     : URL(fileURLWithPath: root).appendingPathComponent(t)
            target = FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
        stamp(); reloadTick += 1
    }

    private func stamp() {
        guard let t = target, t.isFileURL else { lastStamp = nil; return }
        lastStamp = (try? t.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    }

    /// Prueft alle 1,2s, ob sich die Datei geaendert hat.
    private func watchLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard autoReload, let t = target, t.isFileURL else { continue }
            let m = (try? t.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let m, m != lastStamp { lastStamp = m; reloadTick += 1 }
        }
    }
}

struct WebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.setValue(false, forKey: "drawsBackground")
        load(v)
        context.coordinator.token = reloadToken
        return v
    }

    func updateNSView(_ v: WKWebView, context: Context) {
        if context.coordinator.token != reloadToken || context.coordinator.url != url {
            context.coordinator.token = reloadToken
            context.coordinator.url = url
            load(v)
        }
    }

    private func load(_ v: WKWebView) {
        if url.isFileURL {
            v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            v.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var token = -1; var url: URL? = nil }
}
