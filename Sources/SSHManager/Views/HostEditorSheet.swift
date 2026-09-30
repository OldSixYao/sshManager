import AppKit
import SwiftUI

/// 主机的新增/编辑表单。自绘布局（ScrollView + FormSectionCard），
/// 不用 Form(.grouped)：macOS 26 分组表单会把输入内容渲染到右侧。
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormSectionCard(title: "基本") {
                        LabeledField(label: "别名", hint: "空格分隔可设多个") {
                            LeadingTextField(text: $aliasesText)
                        }
                        LabeledField(label: "主机名") {
                            LeadingTextField(text: $draft.hostName)
                        }
                        LabeledField(label: "用户", hint: "可选") {
                            LeadingTextField(text: $draft.user)
                        }
                        LabeledField(label: "端口", hint: "可选，默认 22") {
                            LeadingTextField(text: $draft.port)
                        }
                        LabeledField(label: "分组", hint: "可选") {
                            HStack(spacing: 8) {
                                LeadingTextField(text: $groupText)
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
                    FormSectionCard(title: "认证") {
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
                        LabeledField(label: "保活间隔（秒）", hint: "可选") {
                            LeadingTextField(text: $draft.serverAliveInterval)
                        }
                    }
                    FormSectionCard(title: "跳板 / 代理") {
                        LabeledField(label: "ProxyJump", hint: "可选") {
                            LeadingTextField(text: $draft.proxyJump)
                        }
                        LabeledField(label: "ProxyCommand", hint: "可选") {
                            LeadingTextField(text: $draft.proxyCommand, monospaced: true)
                        }
                    }
                    forwardSection(title: "本地转发", forwards: $draft.localForwards, isRemote: false)
                    forwardSection(title: "远程转发", forwards: $draft.remoteForwards, isRemote: true)
                    FormSectionCard(title: "其他选项（原样写回 config）") {
                        ForEach($draft.otherOptions) { $option in
                            HStack(spacing: 8) {
                                LeadingTextField(placeholder: "键", text: $option.key, monospaced: true)
                                    .frame(width: 160)
                                LeadingTextField(placeholder: "值", text: $option.value, monospaced: true)
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
                .padding(16)
            }

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
        .frame(width: 540, height: 700)
    }

    // MARK: - 表单区块

    private func forwardSection(title: String, forwards: Binding<[PortForward]>, isRemote: Bool) -> some View {
        FormSectionCard(title: title) {
            ForEach(forwards) { $forward in
                HStack(spacing: 8) {
                    LeadingTextField(text: $forward.raw, monospaced: true)
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
