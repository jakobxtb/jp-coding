import SwiftUI

enum MDBlock: Identifiable, Hashable {
    case heading(Int, String)
    case paragraph(String)
    case code(String, String)     // (Sprache, Inhalt)
    case bullets([String])
    case numbered([String])

    var id: String {
        switch self {
        case .heading(let l, let s): return "h\(l)-\(s.hashValue)"
        case .paragraph(let s):      return "p-\(s.hashValue)"
        case .code(let l, let s):    return "c-\(l)-\(s.hashValue)"
        case .bullets(let a):        return "u-\(a.joined().hashValue)"
        case .numbered(let a):       return "n-\(a.joined().hashValue)"
        }
    }
}

enum Markdown {

    static func parse(_ src: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = src.components(separatedBy: .newlines)
        var para: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []

        func flushPara() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para = [] }
        }
        func flushLists() {
            if !bullets.isEmpty { blocks.append(.bullets(bullets)); bullets = [] }
            if !numbers.isEmpty { blocks.append(.numbered(numbers)); numbers = [] }
        }
        func flushAll() { flushPara(); flushLists() }

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)

            if t.hasPrefix("```") {
                flushAll()
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    body.append(lines[i]); i += 1
                }
                blocks.append(.code(lang, body.joined(separator: "\n")))
                i += 1
                continue
            }
            if t.isEmpty { flushAll(); i += 1; continue }
            if t.hasPrefix("### ") { flushAll(); blocks.append(.heading(3, String(t.dropFirst(4)))); i += 1; continue }
            if t.hasPrefix("## ")  { flushAll(); blocks.append(.heading(2, String(t.dropFirst(3)))); i += 1; continue }
            if t.hasPrefix("# ")   { flushAll(); blocks.append(.heading(1, String(t.dropFirst(2)))); i += 1; continue }
            if t.hasPrefix("- ") || t.hasPrefix("* ") {
                flushPara(); bullets.append(String(t.dropFirst(2))); i += 1; continue
            }
            if let r = t.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                flushPara(); numbers.append(String(t[r.upperBound...])); i += 1; continue
            }
            flushLists()
            para.append(line)
            i += 1
        }
        flushAll()
        return blocks
    }

    /// Inline-Auszeichnung: **fett**, `code`, [text](url)
    static func inline(_ s: String, base: Color = Theme.text) -> AttributedString {
        var out = AttributedString("")
        var rest = Substring(s)

        func appendPlain(_ t: Substring) {
            var a = AttributedString(String(t)); a.foregroundColor = base; out += a
        }

        while let m = rest.range(of: #"(\*\*[^*]+\*\*)|(`[^`]+`)|(\[[^\]]+\]\((https?://[^\s)]+)\))"#,
                                 options: .regularExpression) {
            appendPlain(rest[rest.startIndex..<m.lowerBound])
            let tok = String(rest[m])
            if tok.hasPrefix("**") {
                var a = AttributedString(String(tok.dropFirst(2).dropLast(2)))
                a.foregroundColor = Theme.bright; a.font = .system(size: 13, weight: .semibold, design: .monospaced)
                out += a
            } else if tok.hasPrefix("`") {
                var a = AttributedString(String(tok.dropFirst().dropLast()))
                a.foregroundColor = Theme.green
                a.backgroundColor = Theme.green.opacity(0.12)
                a.font = .system(size: 12.5, design: .monospaced)
                out += a
            } else if let close = tok.firstIndex(of: "]"), let open = tok.firstIndex(of: "(") {
                let label = String(tok[tok.index(after: tok.startIndex)..<close])
                let urlStr = String(tok[tok.index(after: open)..<tok.index(before: tok.endIndex)])
                var a = AttributedString(label)
                a.foregroundColor = Theme.green
                a.underlineStyle = .single
                if let u = URL(string: urlStr) { a.link = u }
                out += a
            }
            rest = rest[m.upperBound...]
        }
        appendPlain(rest)
        return out
    }
}
