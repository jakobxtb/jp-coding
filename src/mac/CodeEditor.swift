import SwiftUI
import AppKit

// MARK: - Syntaxfarben

enum Syntax {
    struct Rule { let pattern: String; let color: NSColor }

    static let kw = NSColor(red: 0.78, green: 0.58, blue: 1.00, alpha: 1)   // violett
    static let str = NSColor(red: 1.00, green: 0.78, blue: 0.45, alpha: 1)  // orange
    static let num = NSColor(red: 0.55, green: 0.82, blue: 1.00, alpha: 1)  // blau
    static let com = NSColor(red: 0.40, green: 0.52, blue: 0.48, alpha: 1)  // grau
    static let fn  = NSColor(red: 0.42, green: 0.90, blue: 0.75, alpha: 1)  // türkis
    static let tag = NSColor(red: 0.40, green: 1.00, blue: 0.66, alpha: 1)  // grün
    static let base = NSColor(red: 0.84, green: 0.90, blue: 0.87, alpha: 1)

    static let keywords: [String: [String]] = [
        "swift": ["func","let","var","if","else","guard","return","struct","class","enum","import",
                  "for","while","in","switch","case","default","private","public","static","self",
                  "nil","true","false","try","catch","throws","async","await","extension","protocol"],
        "js": ["function","const","let","var","if","else","return","class","import","export","from",
               "for","while","switch","case","default","new","this","null","true","false","async",
               "await","try","catch","throw","typeof","=>"],
        "py": ["def","class","if","elif","else","return","import","from","for","while","in","not",
               "and","or","None","True","False","try","except","finally","with","as","lambda",
               "yield","async","await","pass","raise"],
        "html": [],
        "css": [],
        "sh": ["if","then","fi","for","do","done","while","case","esac","function","echo","export",
               "local","return","exit"],
    ]

    static func language(for url: URL?) -> String {
        switch (url?.pathExtension ?? "").lowercased() {
        case "swift": return "swift"
        case "js","jsx","ts","tsx","mjs","json": return "js"
        case "py": return "py"
        case "html","htm","xml","svg": return "html"
        case "css","scss","less": return "css"
        case "sh","zsh","bash": return "sh"
        default: return ""
        }
    }

    /// Faerbt den Text ein. Bewusst regelbasiert und schnell, kein voller Parser.
    static func highlight(_ storage: NSTextStorage, lang: String, font: NSFont) {
        let full = NSRange(location: 0, length: storage.length)
        storage.setAttributes([.font: font, .foregroundColor: base], range: full)
        let text = storage.string

        func apply(_ pattern: String, _ color: NSColor, options: NSRegularExpression.Options = []) {
            guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            re.enumerateMatches(in: text, range: full) { m, _, _ in
                if let r = m?.range { storage.addAttribute(.foregroundColor, value: color, range: r) }
            }
        }

        if lang == "html" {
            apply("</?[A-Za-z][\\w:-]*", tag)
            apply("\\s[a-zA-Z-]+(?==)", fn)
        } else if let words = keywords[lang], !words.isEmpty {
            let escaped = words.map { NSRegularExpression.escapedPattern(for: $0) }
            apply("\\b(" + escaped.joined(separator: "|") + ")\\b", kw)
            apply("\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", fn)
        }
        apply("\\b\\d+(\\.\\d+)?\\b", num)
        apply("\"[^\"\\n]*\"|'[^'\\n]*'|`[^`]*`", str)
        if lang == "py" || lang == "sh" {
            apply("#[^\\n]*", com)
        } else if lang == "css" || lang == "html" {
            apply("/\\*[\\s\\S]*?\\*/", com)
            if lang == "html" { apply("<!--[\\s\\S]*?-->", com) }
        } else {
            apply("//[^\\n]*", com)
            apply("/\\*[\\s\\S]*?\\*/", com)
        }
    }
}

// MARK: - Editor

struct SyntaxTextView: NSViewRepresentable {
    @Binding var text: String
    var language: String
    var onChange: () -> Void
    var onSave: () -> Void

    func makeCoordinator() -> Coord { Coord(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Die von AppKit gelieferte Kombination verwenden und NICHT die
        // Textansicht austauschen - ein neuer View am alten Text-Container
        // laesst den Text unsichtbar werden.
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        tv.textColor = Syntax.base
        tv.backgroundColor = NSColor(red: 0.02, green: 0.03, blue: 0.04, alpha: 1)
        tv.drawsBackground = true
        tv.insertionPointColor = NSColor(red: 0.24, green: 1, blue: 0.66, alpha: 1)
        tv.selectedTextAttributes = [.backgroundColor: NSColor(red: 0.24, green: 1, blue: 0.66, alpha: 0.22)]
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 8)

        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = tv.backgroundColor

        context.coordinator.textView = tv
        tv.string = text
        context.coordinator.recolor()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            tv.setSelectedRange(NSRange(location: min(sel.location, text.utf16.count), length: 0))
            context.coordinator.recolor()
        }
    }

    final class Coord: NSObject, NSTextViewDelegate {
        var parent: SyntaxTextView
        weak var textView: NSTextView?
        private var pending: DispatchWorkItem?

        init(_ p: SyntaxTextView) { parent = p }

        func recolor() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
            storage.beginEditing()
            Syntax.highlight(storage, lang: parent.language, font: font)
            storage.endEditing()
        }

        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.text = tv.string
            parent.onChange()
            pending?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.recolor() }
            pending = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
        }

        /// Tab rueckt vier Leerzeichen ein, wie in gaengigen Editoren.
        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertTab(_:)) {
                tv.insertText("    ", replacementRange: tv.selectedRange())
                return true
            }
            return false
        }
    }
}
