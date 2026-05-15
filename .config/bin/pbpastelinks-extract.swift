// pbpastelinks-extract — read the macOS clipboard across every rich-text
// flavor we know about and emit HTML to stdout. Each strategy is a separate
// function so adding a new producer (Notion, Linear, etc.) is a one-liner.
//
// Logging policy: silent on success-path strategies, ONE "hit" line on the
// strategy that worked. If no strategy works, dump one consolidated diagnostic
// block (clipboard flavors + classification + hint).
//
// Exit codes:
//   0 — HTML emitted on stdout
//   2 — clipboard is empty
//   3 — only plain-text flavors present (no rich text on clipboard)
//   4 — rich flavors present but no <a> anchors found in any strategy
//   5 — clipboard appears to be pbpastelinks' own previous output

import Cocoa
import Foundation

let pb = NSPasteboard.general

func log(_ msg: String) {
    FileHandle.standardError.write("[pbpastelinks-extract] \(msg)\n".data(using: .utf8)!)
}

func quote(_ s: String, max: Int = 160) -> String {
    var t = s
    t = t.replacingOccurrences(of: "\n", with: "⏎")
    t = t.replacingOccurrences(of: "\r", with: "⏎")
    t = t.replacingOccurrences(of: "\t", with: "→")
    t = t.replacingOccurrences(of: "'",  with: "ʼ")
    if t.count > max { t = String(t.prefix(max)) + "…" }
    return t
}

func htmlEscape(_ s: String) -> String {
    return s
        .replacingOccurrences(of: "&",  with: "&amp;")
        .replacingOccurrences(of: "<",  with: "&lt;")
        .replacingOccurrences(of: ">",  with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}

func hasAnchor(_ html: String) -> Bool {
    return html.range(of: "<a ", options: .caseInsensitive) != nil
}

// ---------------------------------------------------------------------------
// Strategies: each returns HTML on success, nil otherwise. They never log
// on miss — the bail block summarizes what was on the clipboard if nothing
// works.
// ---------------------------------------------------------------------------

// Apple apps (TextEdit, Mail, Notes), Google Docs (in Chrome), web pages.
func tryPublicHTML() -> String? {
    let s = pb.string(forType: NSPasteboard.PasteboardType("public.html"))
    guard let s = s, !s.isEmpty, hasAnchor(s) else { return nil }
    return s
}

// Chrome, Slack desktop, VS Code, Electron apps.
func tryChromiumWebCustomData() -> String? {
    let type = NSPasteboard.PasteboardType("org.chromium.web-custom-data")
    guard let data = pb.data(forType: type),
          let decoded = String(data: data, encoding: .utf16LittleEndian)
    else { return nil }

    // 2a. Embedded HTML — payload often contains 'text/html' followed by raw markup.
    if let r = decoded.range(of: "<html", options: .caseInsensitive) ??
               decoded.range(of: "<body", options: .caseInsensitive) ??
               decoded.range(of: "<a ",   options: .caseInsensitive) {
        let html = String(decoded[r.lowerBound...])
        if hasAnchor(html) { return html }
    }

    // 2b. Slack Quill delta JSON.
    if let json = findJSONObject(in: decoded, containing: "\"ops\":["),
       let html = quillDeltaToHTML(json),
       hasAnchor(html) {
        return html
    }

    return nil
}

func findJSONObject(in s: String, containing needle: String) -> String? {
    guard let n = s.range(of: needle) else { return nil }
    var start = n.lowerBound
    while s[start] != "{" && start > s.startIndex { start = s.index(before: start) }
    if s[start] != "{" { return nil }

    var depth = 0
    var inString = false
    var escape = false
    var i = start
    while i < s.endIndex {
        let c = s[i]
        if escape { escape = false }
        else if c == "\\" && inString { escape = true }
        else if c == "\"" { inString.toggle() }
        else if !inString {
            if c == "{" { depth += 1 }
            else if c == "}" {
                depth -= 1
                if depth == 0 { return String(s[start...i]) }
            }
        }
        i = s.index(after: i)
    }
    return nil
}

func quillDeltaToHTML(_ json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj  = try? JSONSerialization.jsonObject(with: data),
          let root = obj as? [String: Any],
          let ops  = root["ops"] as? [[String: Any]]
    else { return nil }

    var html = ""
    for op in ops {
        guard let insert = op["insert"] as? String else { continue }
        let escaped = htmlEscape(insert)
        if let attrs = op["attributes"] as? [String: Any],
           let link  = attrs["link"] as? String {
            html += "<a href=\"\(htmlEscape(link))\">\(escaped)</a>"
        } else {
            html += escaped
        }
    }
    return html
}

// Google Docs (non-Chrome), TextEdit, Mail, Word.
func tryPublicRTF() -> String? {
    guard let data = pb.data(forType: NSPasteboard.PasteboardType("public.rtf")) else { return nil }
    guard let attr = try? NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
    ) else { return nil }
    guard let htmlData = try? attr.data(
        from: NSRange(location: 0, length: attr.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
    ), let html = String(data: htmlData, encoding: .utf8),
       hasAnchor(html)
    else { return nil }
    return html
}

// Safari and apps that round-trip via Safari.
func tryAppleWebArchive() -> String? {
    let type = NSPasteboard.PasteboardType("Apple Web Archive pasteboard type")
    guard let data = pb.data(forType: type),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let main = plist["WebMainResource"] as? [String: Any],
          let body = main["WebResourceData"] as? Data,
          let html = String(data: body, encoding: .utf8),
          hasAnchor(html)
    else { return nil }
    return html
}

// ---------------------------------------------------------------------------
// Diagnostics for the bail block
// ---------------------------------------------------------------------------
let plainOnlyMarkers: Set<String> = [
    "public.utf8-plain-text",
    "public.utf16-plain-text",
    "public.utf16-external-plain-text",
    "NSStringPboardType",
    "org.chromium.internal.source-rfh-token",
    "org.chromium.source-url",
]

func looksSelfReferential(_ text: String) -> Bool {
    let lines = text.split(separator: "\n").map { String($0) }
    guard lines.count >= 2 else { return false }
    let urlPattern = try! NSRegularExpression(pattern: "^.+ https?://\\S+$")
    var matches = 0
    for line in lines {
        let s = line.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { continue }
        let range = NSRange(location: 0, length: (s as NSString).length)
        if urlPattern.firstMatch(in: s, range: range) != nil { matches += 1 }
        else { return false }
    }
    return matches >= 2
}

func emitBailDiagnostic(exitCode: Int32, reason: String, hint: String) {
    log("FAIL: \(reason)")
    log("hint: \(hint)")
    log("clipboard had these flavors:")
    let types = pb.types ?? []
    if types.isEmpty {
        log("  (none — clipboard is empty)")
    } else {
        for t in types {
            let n = pb.data(forType: t)?.count ?? 0
            log("  \(t.rawValue) (\(n) bytes)")
        }
    }
    let plain = pb.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
    if let p = plain, !p.isEmpty {
        log("plain text preview: '\(quote(p, max: 200))'")
    }
    exit(exitCode)
}

// ---------------------------------------------------------------------------
// Driver — try strategies in priority order. First hit wins.
// ---------------------------------------------------------------------------
let strategies: [(String, () -> String?)] = [
    ("public.html",                 tryPublicHTML),
    ("chromium-web-custom-data",    tryChromiumWebCustomData),
    ("public.rtf",                  tryPublicRTF),
    ("apple-web-archive",           tryAppleWebArchive),
]

for (name, fn) in strategies {
    if let html = fn() {
        log("strategy='\(name)' result='hit' html_bytes='\(html.utf8.count)'")
        print(html)
        exit(0)
    }
}

// No strategy worked — figure out why and tell the user something useful.
let types = pb.types ?? []
let typeNames = Set(types.map { $0.rawValue })
let hasRich = typeNames.contains { !plainOnlyMarkers.contains($0) }
let plain = pb.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text")) ?? ""

if types.isEmpty {
    emitBailDiagnostic(exitCode: 2,
        reason: "clipboard is empty",
        hint: "copy something first")
}
if !hasRich {
    if looksSelfReferential(plain) {
        emitBailDiagnostic(exitCode: 5,
            reason: "clipboard looks like pbpastelinks own previous output (every line is 'text url')",
            hint: "re-copy from the original source to extract links again")
    }
    emitBailDiagnostic(exitCode: 3,
        reason: "no rich-text flavor on clipboard — only plain text",
        hint: "the source app did not export rich text. re-copy from the rendered view (browser, doc, Slack) — not a terminal or plain-text editor")
}
emitBailDiagnostic(exitCode: 4,
    reason: "rich-text flavor(s) present but no <a> anchors recognized",
    hint: "the clipboard has rich content but none of the known strategies found <a> anchors. check the flavor list above — if you see something not handled (e.g. com.notion.x, application/x-vnd.google-docs-...), tell pbpastelinks to add a strategy for it")
