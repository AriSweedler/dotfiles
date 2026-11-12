// notif-ax — notif-center's native AX engine: reads and presses Notification Center's elements
// through the Accessibility API directly, with no osascript and no System Events round-trips.
//
//   notif-ax LAYOUT press N [--dry-run]     press the Nth notification (1 = newest)
//   notif-ax LAYOUT match NEEDLE [--dry-run] press the first notification whose text has NEEDLE
//   notif-ax tree                            print the AX tree, seven levels deep
//
// stdout is one result line, the contract notif-center's AppleScript engines also keep: "ok",
// "notfound:<n>", "notfound", or "fail: <why>". "fail: accessibility not trusted" means the
// responsible process lacks the Accessibility grant; notif-center then falls back to osascript.
// --dry-run reads everything and presses nothing (logged on stderr instead).
// LAYOUT is a macos/<version>.layout file (DESIGN.md § OS support).
import ApplicationServices
import Darwin

var dryRun = false

func finish(_ result: String) -> Never {
  print(result)
  exit(0)
}

func warn(_ s: String) {
  FileHandle.standardError.write((s + "\n").data(using: .utf8)!)
}

// MARK: layout

struct Step {
  let role: String
  let index: Int
  let optional: Bool
}

struct Layout {
  var alert = ""
  var stack = ""
  var container: [Step] = []
}

func parseLayout(_ path: String) -> Layout {
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
    finish("fail: cannot read layout \(path)")
  }
  var layout = Layout()
  for raw in text.split(separator: "\n") {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if line.isEmpty || line.hasPrefix("#") { continue }
    let words = line.split(separator: " ").map(String.init)
    switch words[0] {
    case "alert": layout.alert = words.count > 1 ? words[1] : ""
    case "stack": layout.stack = words.count > 1 ? words[1] : ""
    case "container":
      for w in words.dropFirst() {
        var token = w
        let optional = token.hasSuffix("?")
        if optional { token.removeLast() }
        let parts = token.split(separator: ":")
        layout.container.append(Step(role: String(parts[0]), index: parts.count > 1 ? Int(parts[1]) ?? 1 : 1, optional: optional))
      }
    default: finish("fail: unknown layout key \(words[0]) in \(path)")
    }
  }
  if layout.alert.isEmpty || layout.stack.isEmpty || layout.container.isEmpty {
    finish("fail: layout \(path) lacks alert, stack or container")
  }
  return layout
}

// MARK: AX

func attr(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
  var value: CFTypeRef?
  return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func string(_ e: AXUIElement, _ name: String) -> String? {
  attr(e, name) as? String
}

func elements(_ e: AXUIElement, _ name: String) -> [AXUIElement] {
  (attr(e, name) as? [AXUIElement]) ?? []
}

func children(_ e: AXUIElement) -> [AXUIElement] { elements(e, kAXChildrenAttribute) }
func role(_ e: AXUIElement) -> String { string(e, kAXRoleAttribute) ?? "" }
func subrole(_ e: AXUIElement) -> String { string(e, kAXSubroleAttribute) ?? "" }

func press(_ e: AXUIElement, _ what: String) -> Bool {
  if dryRun {
    warn("dry-run: press \(what)")
    return true
  }
  return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
}

func pause(_ seconds: Double) { usleep(useconds_t(seconds * 1_000_000)) }

// The NotificationCenter process, by executable path: proc_name truncates to 16 characters.
func notificationCenterPid() -> pid_t? {
  let count = proc_listallpids(nil, 0)
  guard count > 0 else { return nil }
  var pids = [pid_t](repeating: 0, count: Int(count) + 64)
  let got = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
  var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
  for pid in pids.prefix(Int(got)) where pid > 0 {
    if proc_pidpath(pid, &path, UInt32(path.count)) > 0,
       String(cString: path).hasSuffix("/NotificationCenter") {
      return pid
    }
  }
  return nil
}

// The NotificationCenter app element and its windows. A missing Accessibility grant shows up as
// this first call's error, which saves the ~8ms AXIsProcessTrusted() costs.
func app() -> (AXUIElement, [AXUIElement]) {
  guard let pid = notificationCenterPid() else { finish("fail: no NotificationCenter process") }
  let a = AXUIElementCreateApplication(pid)
  AXUIElementSetMessagingTimeout(a, 1.0)
  var value: CFTypeRef?
  let err = AXUIElementCopyAttributeValue(a, kAXWindowsAttribute as CFString, &value)
  if err == .apiDisabled { finish("fail: accessibility not trusted") }
  return (a, (value as? [AXUIElement]) ?? [])
}

func isNotification(_ e: AXUIElement, _ l: Layout) -> Bool {
  let s = subrole(e)
  return s == l.alert || s == l.stack
}

// The element whose children are the alerts and stacks: the layout's container path, where a
// step marked optional is taken only when the element so far does not already start with one.
func container(_ l: Layout) -> AXUIElement {
  let (a, windows) = app()
  if windows.isEmpty { finish("fail: no notification tray") }
  var cur = a
  for step in l.container {
    if step.optional, let first = children(cur).first, isNotification(first, l) { continue }
    let pool = step.role == "AXWindow" ? (cur == a ? windows : elements(cur, kAXWindowsAttribute)) : children(cur).filter { role($0) == step.role }
    guard pool.count >= step.index else { finish("fail: notification container not found") }
    cur = pool[step.index - 1]
  }
  return cur
}

// MARK: commands

func cmdPress(_ n: Int, _ l: Layout) -> Never {
  let grp = container(l)
  if n == 1 {
    let kids = children(grp)
    guard let i = kids.firstIndex(where: { isNotification($0, l) }) else { finish("notfound:0") }
    if subrole(kids[i]) == l.alert {
      finish(press(kids[i], "alert \(i + 1)") ? "ok" : "fail: AXPress refused")
    }
    // A stack's member is pressable only once the stack is expanded, and expanding shifts the
    // layout (a heading, Show Less, Clear All), so re-scan for the first alert.
    _ = press(kids[i], "stack \(i + 1) (expand)")
    if dryRun { finish("ok") }
    var member: AXUIElement?
    for _ in 0..<50 {
      pause(0.02)
      member = children(grp).first { subrole($0) == l.alert }
      if member != nil { break }
    }
    guard let m = member else { finish("fail: stack did not expand") }
    guard press(m, "newest member") else { finish("fail: AXPress refused") }
    // Collapse it again: Show Less is the first of the group's buttons.
    pause(0.1)
    if let showLess = children(grp).first(where: { role($0) == "AXButton" }) {
      _ = press(showLess, "Show Less")
    }
    finish("ok")
  }
  if !dryRun {
    for _ in 0..<40 {
      guard let s = children(grp).first(where: { subrole($0) == l.stack }) else { break }
      _ = press(s, "stack (expand)")
      pause(0.08)
    }
  }
  var idx = 0
  for kid in children(grp) where subrole(kid) == l.alert {
    idx += 1
    if idx == n { finish(press(kid, "alert \(n)") ? "ok" : "fail: AXPress refused") }
  }
  finish("notfound:\(idx)")
}

func cmdMatch(_ needle: String, _ l: Layout) -> Never {
  let grp = container(l)
  for (i, kid) in children(grp).enumerated() where isNotification(kid, l) {
    let text = children(kid)
      .filter { role($0) == kAXStaticTextRole }
      .compactMap { string($0, kAXValueAttribute) }
      .joined(separator: " ")
    guard text.contains(needle) else { continue }
    var target = kid
    if subrole(kid) == l.stack {
      _ = press(kid, "stack \(i + 1) (expand)")
      if dryRun { finish("ok") }
      var expanded = false
      for _ in 0..<25 {
        let now = children(grp)
        if i < now.count, subrole(now[i]) == l.alert {
          target = now[i]
          expanded = true
          break
        }
        pause(0.02)
      }
      guard expanded else { finish("fail: stack did not expand") }
    }
    finish(press(target, "match \(i + 1)") ? "ok" : "fail: AXPress refused")
  }
  finish("notfound")
}

func walk(_ e: AXUIElement, _ depth: Int, _ out: inout String) {
  let desc = string(e, kAXRoleDescriptionAttribute) ?? "missing value"
  let sr = string(e, kAXSubroleAttribute) ?? "missing value"
  out += String(repeating: "  ", count: depth) + "\(string(e, kAXRoleAttribute) ?? "") [\(sr)] \(desc)\n"
  if depth < 7 {
    for c in children(e) { walk(c, depth + 1, &out) }
  }
}

func cmdTree() -> Never {
  let windows = app().1
  var out = "windows=\(windows.count)\n"
  for w in windows { walk(w, 0, &out) }
  print(out, terminator: "")
  exit(0)
}

var args = Array(CommandLine.arguments.dropFirst())
if let i = args.firstIndex(of: "--dry-run") {
  dryRun = true
  args.remove(at: i)
}
switch (args.count, args.first) {
case (1, "tree"): cmdTree()
case (3, _) where args[1] == "press": cmdPress(Int(args[2]) ?? 1, parseLayout(args[0]))
case (3, _) where args[1] == "match": cmdMatch(args[2], parseLayout(args[0]))
default:
  warn("usage: notif-ax LAYOUT press N [--dry-run] | notif-ax LAYOUT match NEEDLE [--dry-run] | notif-ax tree")
  exit(2)
}
