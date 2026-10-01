import Foundation

/// 主流 AI 厂商注册表。vendor 以 id 形式存在 APIKey.vendor 中，
/// 空字符串表示「通用 / 其他」。
/// logoFile 指向 bundle 内 Resources/logos/ 的文件，nil 时徽章回退为单字。
struct AIVendor: Identifiable, Hashable {
    let id: String
    let name: String
    let monogram: String
    let colorHex: UInt32
    var logoFile: String? = nil

    static let custom = AIVendor(id: "", name: "通用 / 其他", monogram: "?", colorHex: 0x8E8E93)

    static let all: [AIVendor] = [
        AIVendor(id: "openai", name: "OpenAI", monogram: "O", colorHex: 0x10A37F, logoFile: "openai.svg"),
        AIVendor(id: "claude", name: "Claude", monogram: "C", colorHex: 0xD97757, logoFile: "anthropic.svg"),
        AIVendor(id: "deepseek", name: "DeepSeek", monogram: "D", colorHex: 0x4D6BFE, logoFile: "deepseek.svg"),
        AIVendor(id: "gemini", name: "Gemini", monogram: "G", colorHex: 0x4285F4, logoFile: "googlegemini.svg"),
        // 智谱 favicon 漂白后仅剩圆角方块轮廓、辨识度差，保留「智」字徽章
        AIVendor(id: "zhipu", name: "智谱 GLM", monogram: "智", colorHex: 0x3859FF),
        AIVendor(id: "kimi", name: "Kimi", monogram: "K", colorHex: 0x1F2937, logoFile: "kimi.svg"),
        AIVendor(id: "qwen", name: "通义千问", monogram: "通", colorHex: 0x615CED, logoFile: "qwen.svg"),
        AIVendor(id: "grok", name: "Grok", monogram: "X", colorHex: 0x1A1A1A, logoFile: "x.svg"),
        AIVendor(id: "mistral", name: "Mistral", monogram: "M", colorHex: 0xFF7000, logoFile: "mistralai.svg"),
        custom,
    ]

    /// 按 id 查找；未知 id（历史数据）回退为通用。
    static func matching(id: String) -> AIVendor {
        all.first { $0.id == id } ?? custom
    }
}
