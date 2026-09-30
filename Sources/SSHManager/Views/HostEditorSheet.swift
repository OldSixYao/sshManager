import AppKit
import SwiftUI

/// 主机的新增/编辑表单。保存时由 ConfigWriter 生成整块并写回 config。
struct HostEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    let session: EditorSession

    @State private var draft: ConfigWriter.Draft
    @State private var aliasesText: String
    @State private var groupText: String
    @State private var validationError: String?

    init(session: EditorSession) {
        self.session = session
        _draft = State(wrappedValue: session.host.map { ConfigWriter.Draft.from($0) } ?? ConfigWriter.Draft())
        _aliasesText = State(wrappedValue: session.host?.aliases.joined(separator: " ") ?? "")
        _groupText = State(wrappedValue: session.group ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                basicSection
                authSection
                proxySection
                forwardSection(title: "本地转发（如 8080:localhost:80）", forwards: $draft.localForwards, isRemote: false)
                forwardSection(title: "远程转发（如 80:127.0.0.1:80）", forwards: $draft.remoteForwards, isRemote: true)
                otherOptionsSection
                if let error = validationError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else if let duplicate = duplicateWarning {
                    Text("提示：别名 \"\(duplicate)\" 已存在，保存后会形成重叠匹配。")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(aliasesText.split(separator: " ").isEmpty)
            }
            .padding(12)
        }
        .frame(width: 540, height: 660)
    }

    // MARK: - 表单区块

    private var basicSection: some View {
        Section("基本") {
            TextField("别名（空格分隔可设多个）", text: $aliasesText)
            TextField("主机名 HostName（IP 或域名）", text: $draft.hostName)
            TextField("用户（可选）", text: $draft.user)
            TextField("端口（可选，默认 22）", text: $draft.port)
            HStack {
                TextField("分组（可选）", text: $groupText)
                if !model.groups.isEmpty {
                    Menu {
                        ForEach(model.groups, id: \.self) { group in
                            Button(group) { groupText = group }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private var authSection: some View {
        Section("认证") {
            ForEach(draft.identityFiles.indices, id: \.self) { index in
                HStack {
                    Text(draft.identityFiles[index])
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        _ = draft.identityFiles.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                pickIdentityFile()
            } label: {
                Label("添加密钥文件…", systemImage: "plus")
            }
            Toggle("仅使用上面的密钥（IdentitiesOnly）", isOn: $draft.identitiesOnly)
            TextField("保活间隔秒数 ServerAliveInterval（可选）", text: $draft.serverAliveInterval)
        }
    }

    private var proxySection: some View {
        Section("跳板 / 代理") {
            TextField("ProxyJump（如 bastion）", text: $draft.proxyJump)
            TextField("ProxyCommand（如 nc -X connect -x 127.0.0.1:7890 %h %p）", text: $draft.proxyCommand)
        }
    }

    private func forwardSection(title: String, forwards: Binding<[PortForward]>, isRemote: Bool) -> some View {
        Section(title) {
            ForEach(forwards) { $forward in
                HStack {
                    TextField("8080:localhost:80", text: $forward.raw)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        forwards.wrappedValue.removeAll { $0.id == forward.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                forwards.wrappedValue.append(PortForward(raw: ""))
            } label: {
                Label(isRemote ? "添加远程转发" : "添加本地转发", systemImage: "plus")
            }
        }
    }

    private var otherOptionsSection: some View {
        Section("其他选项（原样写回 config）") {
            ForEach($draft.otherOptions) { $option in
                HStack {
                    TextField("键", text: $option.key)
                        .frame(width: 160)
                        .font(.system(.body, design: .monospaced))
                    TextField("值", text: $option.value)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        draft.otherOptions.removeAll { $0.id == option.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            Button {
                draft.otherOptions.append(RawOption(key: "", value: ""))
            } label: {
                Label("添加选项", systemImage: "plus")
            }
        }
    }

    // MARK: - 逻辑

    private var duplicateWarning: String? {
        let aliases = aliasesText.split(separator: " ").map(String.init)
        var probe = draft
        probe.aliases = aliases
        return ConfigWriter.duplicateAlias(of: probe, excludingPrimary: session.host?.primaryAlias, in: model.hosts)
    }

    private func save() {
        draft.aliases = aliasesText.split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if let error = ConfigWriter.validate(draft) {
            validationError = error
            return
        }
        validationError = nil
        model.save(
            existing: session.host,
            draft: draft,
            group: groupText.isEmpty ? nil : groupText
        )
        dismiss()
    }

    private func pickIdentityFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = KeyInspector.sshDirectory
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                draft.identityFiles.append(Self.abbreviateHome(url.path))
            }
        }
    }

    static func abbreviateHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
