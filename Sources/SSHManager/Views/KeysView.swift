import AppKit
import SwiftUI

/// 密钥指纹与 known_hosts 管理页。
struct KeysView: View {
    @EnvironmentObject private var model: AppModel

    @State private var keys: [KeyInfo] = []
    @State private var knownHosts = KnownHostsInfo()
    @State private var confirmHash = false
    @State private var actionMessage: String?

    var body: some View {
        List {
            Section("密钥（~/.ssh）") {
                if keys.isEmpty {
                    Text("未找到密钥文件")
                        .foregroundStyle(.secondary)
                }
                ForEach(keys) { key in
                    keyRow(key)
                }
            }

            Section("known_hosts") {
                LabeledContent("记录条数", value: "\(knownHosts.total)")
                LabeledContent("已哈希条目", value: "\(knownHosts.hashed)")
                ForEach(knownHosts.entries) { entry in
                    HStack {
                        Text(entry.host)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                        Text(entry.keyType)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                Button {
                    confirmHash = true
                } label: {
                    Label("哈希化 known_hosts…", systemImage: "eye.slash")
                }
                .disabled(knownHosts.total == 0 || knownHosts.hashed == knownHosts.total)
                if let message = actionMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("密钥与 known_hosts")
        .task {
            reload()
        }
        .confirmationDialog(
            "哈希化 known_hosts？",
            isPresented: $confirmHash,
            titleVisibility: .visible
        ) {
            Button("哈希化") {
                hashKnownHosts()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将把明文主机名替换为不可逆的哈希值（ssh-keygen -H），防止泄露你连接过的主机列表。操作会自动生成 known_hosts.old 备份。")
        }
    }

    private func keyRow(_ key: KeyInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(key.fileName)
                    .fontWeight(.medium)
                if key.fileName.hasSuffix(".pub") {
                    Text("公钥")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                }
                if key.hasPublicPair {
                    Text("有 .pub 配对")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: key.path)])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在访达中显示")
            }
            if let fingerprint = key.fingerprint {
                HStack(spacing: 8) {
                    if let bits = key.bits {
                        Text(bits)
                    }
                    Text(fingerprint)
                    if let type = key.keyType {
                        Text("(\(type))")
                    }
                    if let comment = key.comment {
                        Text(comment)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            } else if let error = key.errorText {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        keys = KeyInspector.listKeys()
        knownHosts = KeyInspector.knownHostsInfo()
        actionMessage = nil
    }

    private func hashKnownHosts() {
        do {
            try KeyInspector.hashKnownHosts()
            reload()
            actionMessage = "已完成哈希化，原文件备份为 known_hosts.old。"
        } catch {
            actionMessage = "哈希化失败：\(error.localizedDescription)"
        }
    }
}
