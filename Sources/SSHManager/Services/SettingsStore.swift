import Foundation

final class SettingsStore: ObservableObject {

    private static let terminalKey = "terminalKind"

    @Published var terminalKind: TerminalKind {
        didSet {
            UserDefaults.standard.set(terminalKind.rawValue, forKey: Self.terminalKey)
        }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.terminalKey),
           let saved = TerminalKind(rawValue: raw) {
            terminalKind = saved
        } else {
            terminalKind = Self.detectedDefault
        }
    }

    static var detectedDefault: TerminalKind {
        let iTermExists = FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
        return iTermExists ? .iterm : .terminalApp
    }
}
