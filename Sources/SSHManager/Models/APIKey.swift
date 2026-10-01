import Foundation

/// 一条 API 密钥记录（LLM 开放接口为主：BaseURL + 密钥 + 模型列表）。
/// provider 为供应商分组名（如「智谱」「OpenRouter」），空字符串表示未分组。
struct APIKey: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var provider: String
    var baseURL: String
    var apiKey: String
    var website: String
    var models: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        provider: String = "",
        baseURL: String,
        apiKey: String,
        website: String = "",
        models: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.website = website
        self.models = models
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? ""
        baseURL = try container.decode(String.self, forKey: .baseURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        website = try container.decodeIfPresent(String.self, forKey: .website) ?? ""
        models = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

    /// 校验，返回 nil 表示通过，否则为错误信息。
    static func validate(name: String, baseURL: String, apiKey: String, models: [String]) -> String? {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "名称不能为空"
        }
        guard APIKeyTester.normalizeBaseURL(baseURL) != nil else {
            return "BaseURL 无效（示例：https://api.example.com/v1）"
        }
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "API Key 不能为空"
        }
        guard models.allSatisfy({ !$0.isEmpty }) else {
            return "模型名称不能为空"
        }
        return nil
    }
}
