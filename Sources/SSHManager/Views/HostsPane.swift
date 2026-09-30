import Combine
import SwiftUI

struct EditorSession: Identifiable {
    let id = UUID()
    let host: SSHHost?
    let group: String?
}

/// 主机管理主区：左列主机列表（搜索/分组过滤），右侧详情面板。
struct HostsPane: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    let group: String?

    @State private var searchText = ""
    @State private var selectedAlias: String?
    @State private var editorSession: EditorSession?
    @State private var hostPendingDelete: SSHHost?

    var body: some View {
        HStack(spacing: 0) {
            hostListColumn
                .frame(width: 300)
            Divider()
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editorSession) { session in
            HostEditorSheet(session: session)
        }
        .confirmationDialog(
            "删除主机 \(hostPendingDelete?.primaryAlias ?? "")？",
            isPresented: Binding(
                get: { hostPendingDelete != nil },
                set: { if !$0 { hostPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let host = hostPendingDelete {
                    model.delete(host)
                    if selectedAlias == host.primaryAlias {
                        selectedAlias = nil
                    }
                }
                hostPendingDelete = nil
            }
            Button("取消", role: .cancel) { hostPendingDelete = nil }
        } message: {
            Text("将从 ~/.ssh/config 中移除该主机的配置块，写入前会自动备份原文件。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .sshmNewHost)) { _ in
            newHost()
        }
    }

    // MARK: - 数据

    private var visibleHosts: [SSHHost] {
        var result = model.hosts
        if let group {
            result = result.filter { model.group(of: $0) == group }
        }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { host in
                if host.primaryAlias.lowercased().contains(query) { return true }
                if (host.hostName ?? "").lowercased().contains(query) { return true }
                if (host.user ?? "").lowercased().contains(query) { return true }
                let tags = model.metadata[host.primaryAlias]?.tags ?? []
                return tags.contains { $0.lowercased().contains(query) }
            }
        }
        return result
    }

    private var concreteHosts: [SSHHost] { visibleHosts.filter { !$0.isPattern } }
    private var patternHosts: [SSHHost] { visibleHosts.filter { $0.isPattern } }

    // MARK: - 列表列

    private var hostListColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("搜索主机…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            List {
                Section("主机") {
                    ForEach(concreteHosts) { host in
                        hostRow(host)
                    }
                }
                if !patternHosts.isEmpty {
                    Section("模式") {
                        ForEach(patternHosts) { host in
                            hostRow(host)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    newHost()
                } label: {
                    Label("新建主机", systemImage: "plus")
                }
            }
            ToolbarItem {
                Button {
                    model.reload()
                } label: {
                    Label("重新加载", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    /// 与侧栏同样的原因（macOS 26 List selection 点击不可靠）：行改为按钮 + 手动高亮
    private func hostRow(_ host: SSHHost) -> some View {
        let isSelected = selectedAlias == host.primaryAlias
        return Button {
            selectedAlias = host.primaryAlias
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(host.primaryAlias)
                        .fontWeight(.medium)
                    if host.isReadOnly {
                        Text("只读")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                    }
                }
                Text(host.targetDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("连接") { connect(host) }
            Button("编辑…") { edit(host) }
            Divider()
            Button("删除…", role: .destructive) { hostPendingDelete = host }
        }
    }

    // MARK: - 详情列

    @ViewBuilder
    private var detailColumn: some View {
        if let alias = selectedAlias,
           let host = visibleHosts.first(where: { $0.primaryAlias == alias }) {
            HostDetailView(host: host)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("选择一台主机查看详情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 动作

    private func newHost() {
        editorSession = EditorSession(host: nil, group: group)
    }

    private func edit(_ host: SSHHost) {
        editorSession = EditorSession(host: host, group: model.group(of: host))
    }

    private func connect(_ host: SSHHost) {
        do {
            try ConnectionHelper.connect(host: host, terminalKind: settings.terminalKind)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// 连接动作的公共入口（详情页与列表右键菜单共用）。
enum ConnectionHelper {
    static func connect(host: SSHHost, terminalKind: TerminalKind) throws {
        guard host.primaryAlias != "*" else {
            throw NSError(domain: "SSHManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "通配符模式块无法直接连接"])
        }
        let result = TerminalLauncher.openSSHSession(kind: terminalKind,
                                                     sshCommand: "ssh \(host.primaryAlias)")
        if !result.succeeded {
            throw NSError(domain: "SSHManager", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "调起终端失败：\(result.trimmedStderr)"])
        }
    }
}
