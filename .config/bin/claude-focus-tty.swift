// claude-focus-tty — emit the frontmost terminal's name and the tty of its
// focused tab/session in one process, replacing two `osascript` invocations
// from claude-session-from-focus.
//
// stdout: "<app>\t<tty>"   e.g. "Terminal\t/dev/ttys000"
// stderr: short diagnostic on failure
// exit  : 0 on success; 1 if frontmost isn't a supported terminal;
//         2 if the AppleScript tty query failed.

import Cocoa

func runAppleScript(_ source: String) -> String? {
    guard let script = NSAppleScript(source: source) else { return nil }
    var error: NSDictionary?
    let result = script.executeAndReturnError(&error)
    if error != nil { return nil }
    return result.stringValue
}

let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""

let tty: String?
switch app {
case "Terminal":
    tty = runAppleScript(
        "tell application \"Terminal\" to get tty of selected tab of front window"
    )
case "iTerm", "iTerm2":
    tty = runAppleScript(
        "tell application \"iTerm2\" to tell current window to tell current session to get tty"
    )
default:
    FileHandle.standardError.write(
        "frontmost not a supported terminal | app='\(app)'\n".data(using: .utf8)!
    )
    exit(1)
}

guard let ttyValue = tty, !ttyValue.isEmpty else {
    FileHandle.standardError.write(
        "failed to read tty | app='\(app)'\n".data(using: .utf8)!
    )
    exit(2)
}

print("\(app)\t\(ttyValue)")
