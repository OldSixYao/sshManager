import SwiftUI

struct APIKeyEditorSession: Identifiable {
    let id = UUID()
    let key: APIKey?
}

/// API 密钥的新增 / 编辑表单。
struct APIKeyEditorSheet: View {
    @EnvironmentObject private var model: APIKeysModel
    @Environment(\.dismiss) private var dismiss

    let session: APIKeyEditorSession

    @State private var name: String
    @State private var baseURL: String
    @State private var website: String
    @State private var apiKey: String
    @State private var showKey: Bool
    @State private var models: [String]
    @State private var validationError: String?

    init(session: APIKeyEditorSession) {
        self.session = session
        _name = State(wrappedValue: session.key?.name ?? "")
        _baseURL = State(wrappedValue: session.key?.baseURL ?? "")
        _website = State(wrappedValue: session.key?.website ?? "")
        _apiKey = State(wrappedValue: session.key?.apiKey ?? "")
        _showKey = State(wrappedValue: session.key == nil)
        _models = State(wrappedValue: session.key?.models ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("基本") {
                    TextField("名称（如：智谱 / DeepSeek）", text: $name)
                    TextField("BaseURL（如：https://api.example.com/v1）", text: $baseURL)
                        .font(.system(.body, design: .monospaced))
                    TextField("网站（服务商控制台，可选）", text: $website)
                }
                Section("密钥") {
                    HStack {
                        if showKey {
                            TextField("sk-…", text: $apiKey)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-…", text: $apiKey)
                                .font(.system(.body, design: .monospaced))
                        }
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Section("模型（每行一个，可多个）") {
                    ForEach(models.indices, id: \.self) { index in
                        HStack {
                            TextField("glm-4.6", text: $models[index])
                                .font(.system(.body, design: .monospaced))
                            Button {
                                _ = models.remove(at: index)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button {
                        models.append("")
                    } label: {
                        Label("添加模型", systemImage: "plus")
                    }
                }
                if let error = validationError {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 560)
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespaces)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        let trimmedModels = models.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        if let error = APIKey.validate(
            name: trimmedName,
            baseURL: trimmedBaseURL,
            apiKey: trimmedKey,
            models: trimmedModels
        ) {
            validationError = error
            return
        }
        validationError = nil

        var key = session.key ?? APIKey(name: trimmedName, baseURL: trimmedBaseURL, apiKey: trimmedKey)
        key.name = trimmedName
        key.baseURL = trimmedBaseURL
        key.apiKey = trimmedKey
        key.website = website.trimmingCharacters(in: .whitespaces)
        key.models = trimmedModels
        _ = model.save(key)
        dismiss()
    }
}
