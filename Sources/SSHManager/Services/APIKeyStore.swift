import Foundation

/// API 密钥的持久化：`~/Library/Application Support/SSHManager/apikeys.json`。
/// 原子写入（临时文件 + rename），权限固定 600。
struct APIKeyStore {

    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("SSHManager", isDirectory: true)
                .appendingPathComponent("apikeys.json")
    }

    /// 文件不存在（首次使用）时返回空数组。
    func load() throws -> [APIKey] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([APIKey].self, from: data)
    }

    func save(_ keys: [APIKey]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(keys)

        let temporary = directory.appendingPathComponent(".apikeys-tmp-\(UUID().uuidString)")
        try data.write(to: temporary)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: fileURL)
        }
    }
}
