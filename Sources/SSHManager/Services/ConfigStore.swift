import Foundation

/// ~/.ssh/config 的读写：原子写入（同目录临时文件 + rename，权限 600）、
/// 写前时间戳备份（保留最近 10 份）。
struct ConfigStore {

    let configURL: URL

    init(configURL: URL? = nil) {
        self.configURL = configURL
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/config")
    }

    static let backupPrefix = "config.sshm-backup-"
    static let maxBackups = 10

    func loadText() throws -> String {
        try String(contentsOf: configURL, encoding: .utf8)
    }

    func save(_ text: String) throws {
        let directory = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: configURL.path) {
            try makeBackup()
        }

        let temporary = directory.appendingPathComponent(".sshm-tmp-\(UUID().uuidString)")
        guard let data = text.data(using: .utf8) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "无法编码为 UTF-8"])
        }
        try data.write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if FileManager.default.fileExists(atPath: configURL.path) {
            _ = try FileManager.default.replaceItemAt(configURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: configURL)
        }
    }

    private func makeBackup() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let directory = configURL.deletingLastPathComponent()

        // 同一秒内多次写入时加序号避免重名
        var backupURL = directory.appendingPathComponent("\(Self.backupPrefix)\(stamp)")
        var serial = 0
        while FileManager.default.fileExists(atPath: backupURL.path) {
            serial += 1
            backupURL = directory.appendingPathComponent("\(Self.backupPrefix)\(stamp)-\(serial)")
        }
        try FileManager.default.copyItem(at: configURL, to: backupURL)

        let backups = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasPrefix(Self.backupPrefix) }
            .sorted()
            .reversed()
        for stale in backups.dropFirst(Self.maxBackups) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(stale))
        }
    }
}
