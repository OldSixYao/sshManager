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

/// 自绘分区卡片：替代 Form(.formStyle(.grouped))。
/// macOS 26 分组表单会把 TextField 的光标/内容渲染到行右侧，Form 内无法修复，
/// 因此表单改为 ScrollView + 本组件的完全自绘布局。
struct FormSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
        }
    }
}

/// 左对齐的文本输入：显式双保险（对齐修饰 + plain 样式），杜绝表单容器的居中/靠右渲染。
struct LeadingTextField: View {
    var placeholder: String = ""
    @Binding var text: String
    var monospaced = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}

/// 左对齐的密码输入（显示为圆点）。
struct LeadingSecureField: View {
    var placeholder: String = ""
    @Binding var text: String
    var monospaced = false

    var body: some View {
        SecureField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.leading)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.045))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            )
    }
}
