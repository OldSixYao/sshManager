import SwiftUI

/// 一条端口转发的展示行：原始配置 + 解析说明 + 运行状态 + 启停按钮。
/// 详情页与转发管理页共用。
struct PortForwardRow: View {
    @EnvironmentObject private var runner: ForwardRunner
    let hostAlias: String
    let forward: PortForward
    let isRemote: Bool

    private var activeEntry: ForwardRunner.RunningForward? {
        runner.running.first {
            $0.hostAlias == hostAlias && $0.spec == forward.raw && $0.isRemote == isRemote
        }
    }

    private var isRunning: Bool {
        guard let entry = activeEntry else { return false }
        return !entry.failed
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isRemote ? "arrow.up.to.line" : "arrow.down.to.line")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(forward.raw)
                    .font(.system(.body, design: .monospaced))
                if let parts = forward.displayParts {
                    Text("\(parts.bind) → \(parts.target)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let entry = activeEntry, entry.failed, let message = entry.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Circle()
                .fill(isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Button(isRunning ? "停止" : "启动") {
                if isRunning, let entry = activeEntry {
                    runner.stop(entry.id)
                } else {
                    runner.start(hostAlias: hostAlias, forward: forward, isRemote: isRemote)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!forward.isValid)
        }
    }
}

/// 全部主机的端口转发管理页。
struct ForwardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var runner: ForwardRunner

    private var hostsForwards: [(host: SSHHost, forwards: [(forward: PortForward, isRemote: Bool)])] {
        model.hosts.compactMap { host in
            var items: [(PortForward, Bool)] = []
            items += host.localForwards.map { ($0, false) }
            items += host.remoteForwards.map { ($0, true) }
            guard !items.isEmpty else { return nil }
            return (host, items.map { (forward: $0.0, isRemote: $0.1) })
        }
    }

    var body: some View {
        List {
            if hostsForwards.isEmpty {
                Text("还没有配置任何端口转发。编辑主机时添加 LocalForward / RemoteForward 即可。")
                    .foregroundStyle(.secondary)
            }
            ForEach(hostsForwards, id: \.host.id) { entry in
                Section(entry.host.primaryAlias) {
                    ForEach(entry.forwards, id: \.forward.id) { item in
                        PortForwardRow(
                            hostAlias: entry.host.primaryAlias,
                            forward: item.forward,
                            isRemote: item.isRemote
                        )
                    }
                }
            }
        }
        .navigationTitle("端口转发")
        .toolbar {
            ToolbarItem {
                Button {
                    runner.stopAll()
                } label: {
                    Label("全部停止", systemImage: "stop.circle")
                }
                .disabled(runner.running.filter { !$0.failed }.isEmpty)
            }
        }
    }
}
