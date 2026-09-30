import Foundation

enum TerminalKind: String, CaseIterable, Identifiable {
    case iterm
    case terminalApp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iterm: return "iTerm2"
        case .terminalApp: return "Terminal.app"
        }
    }
}

/// 通过 AppleScript 调起系统终端并执行 ssh 命令。
/// iTerm2 新建标签页；Terminal.app 新建窗口（其 AppleScript 无免权限的新建标签 API）。
enum TerminalLauncher {

    static func openSSHSession(kind: TerminalKind, sshCommand: String) -> ShellTask.Result {
        let escaped = sshCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        switch kind {
        case .iterm:
            script = """
            tell application "iTerm"
                activate
                if (count of windows) = 0 then
                    create window with default profile
                else
                    tell current window to create tab with default profile
                end if
                delay 0.2
                tell current session of current window to write text "\(escaped)"
            end tell
            """
        case .terminalApp:
            script = """
            tell application "Terminal"
                activate
                do script "\(escaped)"
            end tell
            """
        }
        return ShellTask.run("/usr/bin/osascript", ["-e", script], timeout: 10)
    }
}
