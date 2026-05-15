// pbpastelinks-extract — read the macOS clipboard across every rich-text
// flavor we know about and emit HTML to stdout. Each strategy is a separate
// function so adding a new producer (Notion, Linear, etc.) is a one-liner.
//
// Logs every step to stderr in pbpastelinks's structured "key='value'" format.

import Cocoa
import Foundation

let pb = NSPasteboard.general

func log(_ msg: String) {
    FileHandle.standardError.write("[pbpastelinks-extract] \(msg)\n".data(using: .utf8)!)
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
// Strategy 1: public.html — plain HTML flavor
// Used by: Apple apps (TextEdit, Mail, Notes), some web pages copied in Chrome
// ---------------------------------------------------------------------------
func tryPublicHTML() -> String? {
    guard let s = pb.string(forType: NSPasteboard.PasteboardType("public.html")) else { return nil }
    guard hasAnchor(s) else {
        log("strategy='public.html' result='no anchors in payload' bytes='\(s.utf8.count)'")
        return nil
    }
    log("strategy='public.html' result='hit' bytes='\(s.utf8.count)'")
    return s
}

// ---------------------------------------------------------------------------
// Strategy 2: org.chromium.web-custom-data
// Format: Chromium Pickle of (UTF-16 key, UTF-16 value) pairs. Inside we may
// find `text/html` (standard), `slack/text` (Quill delta JSON), or others.
// Used by: Chrome, Slack desktop, VS Code, Electron apps in general.
// ---------------------------------------------------------------------------
func tryChromiumWebCustomData() -> String? {
    let type = NSPasteboard.PasteboardType("org.chromium.web-custom-data")
    guard let data = pb.data(forType: type) else { return nil }
    log("strategy='chromium-web-custom-data' bytes='\(data.count)' decoding=...")

    // Best-effort: decode entire blob as UTF-16-LE, then scan for known patterns.
    // Chromium's exact Pickle layout is fiddly and varies; pattern-scanning is
    // robust to layout drift.
    guard let decoded = String(data: data, encoding: .utf16LittleEndian) else {
        log("strategy='chromium-web-custom-data' result='not utf16-le decodable'")
        return nil
    }

    // 2a. Embedded text/html (key) followed by HTML payload
    if let htmlRange = decoded.range(of: "<html", options: .caseInsensitive) ??
                       decoded.range(of: "<body", options: .caseInsensitive) ??
                       decoded.range(of: "<a ",   options: .caseInsensitive) {
        // Walk from htmlRange forward; emit everything to end (perl will only
        // match real anchors).
        let html = String(decoded[htmlRange.lowerBound...])
        if hasAnchor(html) {
            log("strategy='chromium-web-custom-data/text-html' result='hit' bytes='\(html.utf8.count)'")
            return html
        }
    }

    // 2b. Slack Quill delta JSON: {"ops":[{"insert":"...","attributes":{"link":"..."}}, ...]}
    if let json = findJSONObject(in: decoded, after: "{\"ops\":[") {
        if let html = quillDeltaToHTML(json) {
            if hasAnchor(html) {
                log("strategy='chromium-web-custom-data/slack-quill' result='hit' bytes='\(html.utf8.count)'")
                return html
            }
            log("strategy='chromium-web-custom-data/slack-quill' result='no link attributes in delta'")
        }
    }

    log("strategy='chromium-web-custom-data' result='no recognized payload'")
    return nil
}

// Find a balanced JSON object starting at the first occurrence of `prefix`.
// Walks brace depth; ignores braces inside JSON strings.
func findJSONObject(in s: String, after prefix: String) -> String? {
    guard let pr = s.range(of: prefix) else { return nil }
    // Walk backwards from pr.lowerBound to find the opening `{`
    var start = pr.lowerBound
    while start > s.startIndex {
        let prev = s.index(before: start)
        if s[prev] == "{" { start = prev; break }
        start = prev
    }
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

// Quill delta → minimal HTML: text runs with `attributes.link` become anchors.
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

// ---------------------------------------------------------------------------
// Strategy 3: public.rtf → NSAttributedString → HTML
// Used by: Google Docs (when not in Chrome custom mode), TextEdit, Mail, Word.
// ---------------------------------------------------------------------------
func tryPublicRTF() -> String? {
    guard let data = pb.data(forType: NSPasteboard.PasteboardType("public.rtf")) else { return nil }
    guard let attr = try? NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
    ) else {
        log("strategy='public.rtf' result='NSAttributedString init failed'")
        return nil
    }
    guard let htmlData = try? attr.data(
        from: NSRange(location: 0, length: attr.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
    ), let html = String(data: htmlData, encoding: .utf8) else {
        log("strategy='public.rtf' result='HTML export failed'")
        return nil
    }
    guard hasAnchor(html) else {
        log("strategy='public.rtf' result='no anchors after RTF→HTML' bytes='\(html.utf8.count)'")
        return nil
    }
    log("strategy='public.rtf' result='hit' bytes='\(html.utf8.count)'")
    return html
}

// ---------------------------------------------------------------------------
// Strategy 4: Apple Web Archive — plist containing HTML + resources
// Used by: Safari and apps that round-trip via Safari.
// ---------------------------------------------------------------------------
func tryAppleWebArchive() -> String? {
    let type = NSPasteboard.PasteboardType("Apple Web Archive pasteboard type")
    guard let data = pb.data(forType: type) else { return nil }
    guard let plist = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil
    ) as? [String: Any] else {
        log("strategy='apple-web-archive' result='plist parse failed'")
        return nil
    }
    guard let main = plist["WebMainResource"] as? [String: Any],
          let body = main["WebResourceData"] as? Data,
          let html = String(data: body, encoding: .utf8) else {
        log("strategy='apple-web-archive' result='no WebResourceData')")
        return nil
    }
    guard hasAnchor(html) else {
        log("strategy='apple-web-archive' result='no anchors' bytes='\(html.utf8.count)'")
        return nil
    }
    log("strategy='apple-web-archive' result='hit' bytes='\(html.utf8.count)'")
    return html
}

// ---------------------------------------------------------------------------
// Driver: list all flavors (for debugging), then try strategies in priority
// order. Print HTML to stdout if any hits; exit 3 with diagnostics otherwise.
// ---------------------------------------------------------------------------
let types = pb.types ?? []
for t in types {
    let n = pb.data(forType: t)?.count ?? 0
    log("clipboard flavor | name='\(t.rawValue)' bytes='\(n)'")
}

let strategies: [(String, () -> String?)] = [
    ("public.html",                 tryPublicHTML),
    ("chromium-web-custom-data",    tryChromiumWebCustomData),
    ("public.rtf",                  tryPublicRTF),
    ("apple-web-archive",           tryAppleWebArchive),
]

for (name, fn) in strategies {
    if let html = fn() {
        log("picked | strategy='\(name)' bytes='\(html.utf8.count)'")
        print(html)
        exit(0)
    }
}

log("no anchors extractable from any known flavor | hint='paste into TextEdit to confirm rich text exists; if not, re-copy from rendered view (not terminal/plain-text)'")
exit(3)
