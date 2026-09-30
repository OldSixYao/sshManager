import SwiftUI

/// 表单字段：小标签在上方（可带灰色提示），输入控件独占一行。
/// 统一替代「占位文字当标签 + 塞示例」的旧样式。
struct LabeledField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var field: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.callout.weight(.medium))
                if let hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            field
        }
        .padding(.vertical, 2)
    }
}
