import SwiftUI
import AppKit

/// Eingabefeld mit CLI-Tastaturverhalten: Enter sendet, Shift+Enter neue Zeile,
/// Tab vervollstaendigt, Pfeiltasten steuern die Befehlsliste, Escape schliesst sie.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var popupOpen: Bool
    var onSubmit: () -> Void
    var onMove: (Int) -> Void        // -1 hoch, +1 runter
    var onComplete: () -> Void       // Tab
    var onEscape: () -> Void
    var onHistory: (Int) -> Void     // Verlauf, wenn keine Liste offen

    func makeCoordinator() -> Coord { Coord(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textColor = NSColor(Theme.text)
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.insertionPointColor = NSColor(Theme.green)
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 2, height: 5)
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        context.coordinator.textView = tv
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            let loc = min(sel.location, text.utf16.count)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
        }
    }

    final class Coord: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?
        init(_ p: ComposerTextView) { parent = p }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if NSEvent.modifierFlags.contains(.shift) {
                    tv.insertNewlineIgnoringFieldEditor(nil); return true
                }
                if parent.popupOpen { parent.onComplete(); return true }
                parent.onSubmit(); return true

            case #selector(NSResponder.insertTab(_:)):
                if parent.popupOpen { parent.onComplete(); return true }
                return false

            case #selector(NSResponder.moveUp(_:)):
                if parent.popupOpen { parent.onMove(-1); return true }
                if tv.string.isEmpty { parent.onHistory(-1); return true }
                return false

            case #selector(NSResponder.moveDown(_:)):
                if parent.popupOpen { parent.onMove(1); return true }
                return false

            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true

            default: return false
            }
        }
    }
}

// MARK: - Slash-Befehle

struct SlashCmd: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var desc: String
    var isApp: Bool
}

enum Slash {
    /// In der App selbst ausgefuehrt - die CLI kann diese im Programm-Modus nicht.
    static let app: [SlashCmd] = [
        .init(name: "new",         desc: "Neuen Chat anlegen, Ordner waehlen", isApp: true),
        .init(name: "folder",      desc: "Arbeitsordner dieses Chats wechseln", isApp: true),
        .init(name: "model",       desc: "Modell wechseln", isApp: true),
        .init(name: "test",        desc: "Modell testen und bei Ausfall ersetzen", isApp: true),
        .init(name: "permissions", desc: "Berechtigungsstufe umschalten", isApp: true),
        .init(name: "attach",      desc: "Dateien anhaengen", isApp: true),
        .init(name: "code",        desc: "Datei-Editor ein- und ausblenden", isApp: true),
        .init(name: "preview",     desc: "Live-Vorschau ein- und ausblenden", isApp: true),
        .init(name: "skills",      desc: "Skills verwalten", isApp: true),
        .init(name: "settings",    desc: "Einstellungen oeffnen", isApp: true),
        .init(name: "export",      desc: "Chat als Markdown speichern", isApp: true),
        .init(name: "clear",       desc: "Verlauf leeren, neue Sitzung", isApp: true),
        .init(name: "stop",        desc: "Laufende Ausfuehrung abbrechen", isApp: true),
        .init(name: "proxy",       desc: "Proxy neu starten", isApp: true),
        .init(name: "help",        desc: "Alle Befehle anzeigen", isApp: true),
    ]

    /// Von der CLI gemeldete Befehle (Skills und eingebaute), minus die, die die App selbst macht.
    static func merged(cli: [String]) -> [SlashCmd] {
        let appNames = Set(app.map { $0.name })
        let fromCLI = cli.filter { !appNames.contains($0) }
            .sorted()
            .map { SlashCmd(name: $0, desc: "an Claude Code weitergeben", isApp: false) }
        return app + fromCLI
    }

    static func filter(_ all: [SlashCmd], query: String) -> [SlashCmd] {
        let q = query.lowercased()
        if q.isEmpty { return all }
        let starts = all.filter { $0.name.lowercased().hasPrefix(q) }
        let contains = all.filter { !$0.name.lowercased().hasPrefix(q) && $0.name.lowercased().contains(q) }
        return starts + contains
    }

    /// Liefert das Praefix nach "/" wenn die Zeile ein Befehl in Eingabe ist.
    static func query(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let rest = String(text.dropFirst())
        if rest.contains(" ") || rest.contains("\n") { return nil }
        return rest
    }
}
