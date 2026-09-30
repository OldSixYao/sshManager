import Combine
import Foundation

/// 应用级状态：主机列表、分组元数据、config 读写与监听。
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var hosts: [SSHHost] = []
    @Published private(set) var metadata: [String: HostMetadata] = [:]
    @Published var errorMessage: String?
    @Published private(set) var configPath: String

    private let store = ConfigStore()
    private var watcher: ConfigWatcher?

    init() {
        configPath = store.configURL.path
        loadMetadata()
        reload()

        let newWatcher = ConfigWatcher(path: configPath)
        newWatcher.onChange = { [weak self] in
            self?.reload()
        }
        newWatcher.start()
        watcher = newWatcher
    }

    func reload() {
        do {
            hosts = try ConfigParser.parseFile(at: store.configURL).hosts
        } catch {
            errorMessage = "读取 ~/.ssh/config 失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 分组

    var groups: [String] {
        Array(Set(metadata.values.compactMap(\.group))).sorted()
    }

    var concreteHostCount: Int {
        hosts.filter { !$0.isPattern }.count
    }

    func hosts(in group: String) -> [SSHHost] {
        hosts.filter { metadata[$0.primaryAlias]?.group == group }
    }

    func group(of host: SSHHost) -> String? {
        metadata[host.primaryAlias]?.group
    }

    func setGroup(_ host: SSHHost, to group: String?) {
        setGroupRaw(alias: host.primaryAlias, to: group)
        persistMetadata()
    }

    private func setGroupRaw(alias: String, to group: String?) {
        guard !alias.isEmpty else { return }
        var meta = metadata[alias] ?? HostMetadata()
        meta.group = group
        if meta.isEmpty {
            metadata.removeValue(forKey: alias)
        } else {
            metadata[alias] = meta
        }
    }

    // MARK: - 增删改

    func save(existing: SSHHost?, draft: ConfigWriter.Draft, group: String?) {
        do {
            let lines = ConfigParser.normalizeLines(try store.loadText())
            let newLines: [String]
            if let host = existing {
                guard host.sourceFile == store.configURL.path else {
                    errorMessage = "该主机来自 Include 文件，暂不支持在应用内编辑"
                    return
                }
                newLines = ConfigWriter.replacing(host: host, draft: draft, in: lines)
                let newPrimary = draft.aliases.first ?? host.primaryAlias
                if newPrimary != host.primaryAlias, let meta = metadata[host.primaryAlias] {
                    metadata.removeValue(forKey: host.primaryAlias)
                    metadata[newPrimary] = meta
                }
            } else {
                newLines = ConfigWriter.appending(draft: draft, to: lines)
            }
            try store.save(ConfigWriter.text(of: newLines))
            setGroupRaw(alias: draft.aliases.first ?? "", to: group)
            persistMetadata()
            reload()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    func delete(_ host: SSHHost) {
        guard host.sourceFile == store.configURL.path else {
            errorMessage = "该主机来自 Include 文件，暂不支持在应用内删除"
            return
        }
        do {
            let lines = ConfigParser.normalizeLines(try store.loadText())
            try store.save(ConfigWriter.text(of: ConfigWriter.removing(host: host, from: lines)))
            metadata.removeValue(forKey: host.primaryAlias)
            persistMetadata()
            reload()
        } catch {
            errorMessage = "删除失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 元数据持久化

    private var metadataURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SSHManager", isDirectory: true)
            .appendingPathComponent("metadata.json")
    }

    private func loadMetadata() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([String: HostMetadata].self, from: data)
        else { return }
        metadata = decoded
    }

    private func persistMetadata() {
        try? FileManager.default.createDirectory(
            at: metadataURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL)
        }
    }
}
