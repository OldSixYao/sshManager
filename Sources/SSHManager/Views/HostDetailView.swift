import SwiftUI

/// 主机详情：连接信息、快速连接、端口转发启停、生效配置、known_hosts 状态。
struct HostDetailView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var runner: ForwardRunner
    let host: SSHHost

    @State private var editorSession: EditorSession?
    @State private var confirmDelete = false
    @State private var keyFingerprints: [String: String] = [:]
    @State private var knownHostLine: String?
    @State private var effectiveConfigText: String?
    @State private var showEffectiveConfig = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionRow
                infoSection
                if !host.localForwards.isEmpty || !host.remoteForwards.isEmpty {
                    forwardSection
                }
                if !host.otherOptions.isEmpty {
                    optionsSection
                }
                footerSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(host.primaryAlias)
        .sheet(item: $editorSession) { session in
            HostEditorSheet(session: session)
        }
        .sheet(isPresented: $showEffectiveConfig) {
            EffectiveConfigSheet(alias: host.primaryAlias, text: effectiveConfigText)
        }
        .confirmationDialog(
            "删除主机 \(host.primaryAlias)？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { model.delete(host) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从 ~/.ssh/config 中移除该主机的配置块，写入前会自动备份原文件。")
        }
        .task(id: host.id) {
            await loadExtras()
        }
    }

    // MARK: - 区块

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.primaryAlias)
                    .font(.largeTitle.bold())
                Text(host.targetDescription)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("分组", selection: Binding(
                get: { model.group(of: host) ?? "" },
                set: { model.setGroup(host, to: $0.isEmpty ? nil : $0) }
            )) {
                Text("未分组").tag("")
                ForEach(model.groups, id: \.self) { group in
                    Text(group).tag(group)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                connect()
            } label: {
                Label("连接", systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
            .disabled(host.primaryAlias == "*")

            Button("编辑…") {
                editorSession = EditorSession(host: host, group: model.group(of: host))
            }
            .disabled(!host.isEditable)

            Button("删除…", role: .destructive) {
                confirmDelete = true
            }
            .disabled(!host.isEditable)

            Spacer()

            Button {
                loadEffectiveConfig()
            } label: {
                Label("查看生效配置", systemImage: "doc.text.magnifyingglass")
            }
            .disabled(host.isPattern)
        }
    }

    private var infoSection: some View {
        section("连接信息") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    keyLabel("主机名")
                    valueLabel(host.hostName ?? "—")
                }
                GridRow {
                    keyLabel("用户")
                    valueLabel(host.user ?? "当前用户")
                }
                GridRow {
                    keyLabel("端口")
                    valueLabel(host.port ?? "22")
                }
                ForEach(host.identityFiles, id: \.self) { file in
                    GridRow {
                        keyLabel("密钥")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file)
                                .font(.system(.body, design: .monospaced))
                            if let fingerprint = keyFingerprints[file] {
                                Text(fingerprint)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !host.isPattern {
                                Text("指纹读取中…")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if host.identitiesOnly == true {
                    GridRow {
                        keyLabel("仅用指定密钥")
                        valueLabel("IdentitiesOnly yes")
                    }
                }
                if let interval = host.serverAliveInterval {
                    GridRow {
                        keyLabel("保活间隔")
                        valueLabel("\(interval) 秒")
                    }
                }
                if let jump = host.proxyJump, !jump.isEmpty {
                    GridRow {
                        keyLabel("跳板 ProxyJump")
                        valueLabel(jump)
                    }
                }
                if let command = host.proxyCommand, !command.isEmpty {
                    GridRow {
                        keyLabel("代理 ProxyCommand")
                        Text(command)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var forwardSection: some View {
        section("端口转发") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(host.localForwards) { forward in
                    PortForwardRow(hostAlias: host.primaryAlias, forward: forward, isRemote: false)
                }
                ForEach(host.remoteForwards) { forward in
                    PortForwardRow(hostAlias: host.primaryAlias, forward: forward, isRemote: true)
                }
            }
        }
    }

    private var optionsSection: some View {
        section("其他选项") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(host.otherOptions) { option in
                    HStack(alignment: .top, spacing: 8) {
                        Text(option.key)
                            .fontWeight(.medium)
                            .frame(width: 150, alignment: .leading)
                        Text(option.value)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private var footerSection: some View {
        section("来源") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(host.sourceFile)（第 \(host.blockStart + 1)–\(host.blockEnd) 行）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if host.isReadOnly {
                    Label("该主机来自 Include 引用的文件，暂不支持在应用内编辑。", systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !host.isPattern {
                    if let line = knownHostLine {
                        Label("known_hosts 已记录该主机的指纹", systemImage: "checkmark.shield.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.tail)
                    } else {
                        Label("known_hosts 中尚无该主机记录（首次连接时会写入）", systemImage: "checkmark.shield")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - 动作

    private func connect() {
        do {
            try ConnectionHelper.connect(host: host, terminalKind: settings.terminalKind)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func loadEffectiveConfig() {
        let alias = host.primaryAlias
        Task.detached {
            do {
                let text = try KeyInspector.effectiveConfig(alias: alias)
                await MainActor.run {
                    effectiveConfigText = text
                    showEffectiveConfig = true
                }
            } catch {
                await MainActor.run {
                    model.errorMessage = "读取生效配置失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func loadExtras() async {
        let files = host.identityFiles
        let alias = host.primaryAlias
        let fingerprints = await Task.detached {
            var result: [String: String] = [:]
            for file in files {
                if let line = KeyInspector.fingerprintLine(forFile: file) {
                    result[file] = line
                }
            }
            return result
        }.value
        keyFingerprints = fingerprints

        guard !host.isPattern else { return }
        let line = await Task.detached {
            KeyInspector.lookupKnownHost(host: alias)
        }.value
        knownHostLine = line
    }

    // MARK: - 小部件

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    private func keyLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 130, alignment: .leading)
    }

    private func valueLabel(_ text: String) -> some View {
        Text(text)
            .textSelection(.enabled)
    }
}

struct EffectiveConfigSheet: View {
    let alias: String
    let text: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text ?? "读取中…")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            Divider()
            HStack {
                Text("等同命令：ssh -G \(alias)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(10)
        }
        .frame(width: 580, height: 500)
    }
}
