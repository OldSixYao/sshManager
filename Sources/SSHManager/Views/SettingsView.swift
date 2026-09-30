import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @State private var sshVersionText = "…"
    @State private var iTermInstalled = false

    var body: some View {
        Form {
            Section("连接") {
                Picker("调起的终端", selection: $settings.terminalKind) {
                    ForEach(TerminalKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("iTerm2 会在当前窗口新建标签页；Terminal.app 会新建窗口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("环境") {
                LabeledContent("SSH 版本", value: sshVersionText)
                LabeledContent("配置文件", value: "~/.ssh/config")
            }
        }
        .formStyle(.grouped)
        .task {
            sshVersionText = await Task.detached { KeyInspector.sshVersion() }.value
            iTermInstalled = FileManager.default.fileExists(atPath: "/Applications/iTerm.app")
        }
    }
}
