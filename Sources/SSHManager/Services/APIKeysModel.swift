import Combine
import Foundation

/// API 密钥的应用级状态：内存列表 + 自动持久化。
@MainActor
final class APIKeysModel: ObservableObject {

    @Published private(set) var keys: [APIKey] = []
    @Published var errorMessage: String?

    private let store: APIKeyStore

    init(store: APIKeyStore = APIKeyStore()) {
        self.store = store
        reload()
    }

    func reload() {
        do {
            keys = try store.load()
        } catch {
            errorMessage = "读取 API 密钥失败：\(error.localizedDescription)"
        }
    }

    /// 新增或更新（按 id 判断），成功返回 true。
    @discardableResult
    func save(_ key: APIKey) -> Bool {
        do {
            if let index = keys.firstIndex(where: { $0.id == key.id }) {
                keys[index] = key
            } else {
                keys.append(key)
            }
            try persist()
            return true
        } catch {
            errorMessage = "保存 API 密钥失败：\(error.localizedDescription)"
            return false
        }
    }

    func delete(_ key: APIKey) {
        do {
            keys.removeAll { $0.id == key.id }
            try persist()
        } catch {
            errorMessage = "删除 API 密钥失败：\(error.localizedDescription)"
        }
    }

    private func persist() throws {
        try store.save(keys)
    }
}
