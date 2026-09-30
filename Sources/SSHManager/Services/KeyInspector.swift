import Foundation

struct KeyInfo: Identifiable {
    var id: String { path }
    let path: String
    let fileName: String
    let bits: String?
    let fingerprint: String?
    let keyType: String?
    let comment: String?
    let hasPublicPair: Bool
    let errorText: String?
}

struct KnownHostEntry: Identifiable {
    let id: Int
    let host: String
    let keyType: String
    let isHashed: Bool
}

struct KnownHostsInfo {
    var total = 0
    var hashed = 0
    var entries: [KnownHostEntry] = []
}

/// 密钥指纹 / known_hosts / 生效配置等，全部通过系统 ssh 工具子进程获取，
/// 不自己实现任何密码学。
enum KeyInspector {

    static var sshDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
    }

    static func expandTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func listKeys(sshDirectory directory: URL = sshDirectory) -> [KeyInfo] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else { return [] }

        let excludedNames: Set<String> = ["config", "known_hosts", "authorized_keys", "authorized_keys2"]
        var result: [KeyInfo] = []
        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            guard !excludedNames.contains(name) else { continue }
            guard !name.hasSuffix(".old") else { continue }
            guard !name.contains(ConfigStore.backupPrefix) else { continue }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }

            let isPublicKey = name.hasSuffix(".pub")
            let hasPublicPair = isPublicKey
                || FileManager.default.fileExists(atPath: url.path + ".pub")
            let output = ShellTask.run("/usr/bin/ssh-keygen", ["-lf", url.path])

            if output.succeeded, let line = output.trimmedStdout.split(separator: "\n").first {
                let parts = line.split(separator: " ").map(String.init)
                let bits = parts.first
                let fingerprint = parts.dropFirst().first
                let type = parts.last.flatMap { $0.hasPrefix("(") && $0.hasSuffix(")") ? String($0.dropFirst().dropLast()) : nil }
                let commentParts = parts.dropFirst(2).dropLast(parts.count > 2 ? 1 : 0)
                let comment = commentParts.joined(separator: " ")
                result.append(KeyInfo(
                    path: url.path,
                    fileName: name,
                    bits: bits,
                    fingerprint: fingerprint,
                    keyType: type,
                    comment: comment.isEmpty ? nil : comment,
                    hasPublicPair: hasPublicPair,
                    errorText: nil
                ))
            } else {
                let message = output.trimmedStderr.split(separator: "\n").last.map(String.init) ?? "无法读取指纹"
                result.append(KeyInfo(
                    path: url.path,
                    fileName: name,
                    bits: nil,
                    fingerprint: nil,
                    keyType: nil,
                    comment: nil,
                    hasPublicPair: hasPublicPair,
                    errorText: message
                ))
            }
        }
        return result
    }

    /// 对单个密钥文件取 "3072 SHA256:… comment (RSA)" 一行的指纹部分，失败返回 nil。
    static func fingerprintLine(forFile path: String) -> String? {
        let expanded = expandTilde(path)
        let output = ShellTask.run("/usr/bin/ssh-keygen", ["-lf", expanded])
        guard output.succeeded else { return nil }
        return output.trimmedStdout.split(separator: "\n").first.map(String.init)
    }

    static func knownHostsInfo(sshDirectory directory: URL = sshDirectory) -> KnownHostsInfo {
        let url = directory.appendingPathComponent("known_hosts")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return KnownHostsInfo() }
        var info = KnownHostsInfo()
        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("@") else { continue }
            let fields = line.split(separator: " ").map(String.init)
            guard let host = fields.first else { continue }
            info.total += 1
            let hashed = host.hasPrefix("|")
            if hashed { info.hashed += 1 }
            info.entries.append(KnownHostEntry(
                id: index,
                host: hashed ? "（已哈希）" : host,
                keyType: fields.count > 1 ? fields[1] : "未知类型",
                isHashed: hashed
            ))
        }
        return info
    }

    /// ssh-keygen -F 查询主机指纹；返回匹配的记录行，未找到返回 nil。
    static func lookupKnownHost(host: String, sshDirectory directory: URL = sshDirectory) -> String? {
        let output = ShellTask.run("/usr/bin/ssh-keygen", ["-F", host, "-f", directory.appendingPathComponent("known_hosts").path])
        guard output.succeeded else { return nil }
        let lines = output.trimmedStdout.split(separator: "\n").map(String.init)
        return lines.last { !$0.hasPrefix("#") }
    }

    /// 哈希化 known_hosts（ssh-keygen 自带 -H，会自动生成 known_hosts.old 备份）。
    static func hashKnownHosts(sshDirectory directory: URL = sshDirectory) throws {
        let knownHosts = directory.appendingPathComponent("known_hosts").path
        let output = ShellTask.run("/usr/bin/ssh-keygen", ["-H", "-f", knownHosts])
        guard output.succeeded else {
            throw NSError(domain: "KeyInspector", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: output.trimmedStderr])
        }
    }

    /// ssh -G 输出该别名最终生效的完整配置。
    static func effectiveConfig(alias: String) throws -> String {
        let output = ShellTask.run("/usr/bin/ssh", ["-G", alias])
        guard output.succeeded else {
            throw NSError(domain: "KeyInspector", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: output.trimmedStderr])
        }
        return output.stdout
    }

    static func sshVersion() -> String {
        let output = ShellTask.run("/usr/bin/ssh", ["-V"])
        return output.trimmedStderr.isEmpty ? output.trimmedStdout : output.trimmedStderr
    }
}
