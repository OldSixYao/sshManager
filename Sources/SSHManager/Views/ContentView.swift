import SwiftUI

enum SidebarSelection: Hashable {
    case allHosts
    case group(String)
    case forwarding
    case keys
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var runner: ForwardRunner
    @State private var selection: SidebarSelection? = .allHosts

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            detailPane
        }
        .alert("出错了", isPresented: errorBinding) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection {
        case .forwarding:
            ForwardingView()
        case .keys:
            KeysView()
        default:
            HostsPane(group: groupFilter)
        }
    }

    private var groupFilter: String? {
        if case .group(let group) = selection { return group }
        return nil
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var selection: SidebarSelection?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle("主机")
                SidebarRow(selection: $selection, value: .allHosts,
                           title: "全部主机", systemImage: "server.rack",
                           badge: model.concreteHostCount)
                ForEach(model.groups, id: \.self) { group in
                    SidebarRow(selection: $selection, value: .group(group),
                               title: group, systemImage: "folder",
                               badge: model.hosts(in: group).count)
                }
                sectionTitle("工具")
                    .padding(.top, 12)
                SidebarRow(selection: $selection, value: .forwarding,
                           title: "端口转发", systemImage: "arrow.left.arrow.right")
                SidebarRow(selection: $selection, value: .keys,
                           title: "密钥与 known_hosts", systemImage: "key")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("SSH Manager")
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
    }
}

/// 显式按钮行 + 手动高亮：macOS 26 侧栏 List 的 selection 机制存在点击不生效的
/// 兼容性问题，改用纯状态驱动保证任何系统版本下点击都可靠。
struct SidebarRow: View {
    @Binding var selection: SidebarSelection?
    let value: SidebarSelection
    let title: String
    let systemImage: String
    var badge: Int?

    private var isSelected: Bool { selection == value }

    var body: some View {
        Button {
            selection = value
        } label: {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                Text(title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text("\(badge)")
                        .font(.caption)
                        .foregroundStyle(isSelected ? Color.primary.opacity(0.65) : Color.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
    }
}
