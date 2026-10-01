import SwiftUI

struct APIKeyEditorSession: Identifiable {
    let id = UUID()
    let key: APIKey?
}

/// API 密钥的新增 / 编辑表单。自绘布局（ScrollView + FormSectionCard），
/// 不用 Form(.grouped)：macOS 26 分组表单会把输入内容渲染到右侧。
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
    @State private var isFetchingModels = false
    @State private var fetchMessage: String?
    @State private var fetchFailed = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    FormSectionCard(title: "基本") {
                        LabeledField(label: "名称") {
                            LeadingTextField(text: $name)
                        }
                        LabeledField(label: "BaseURL") {
                            LeadingTextField(text: $baseURL, monospaced: true)
                        }
                        LabeledField(label: "网站", hint: "服务商控制台，可选") {
                            LeadingTextField(text: $website)
                        }
                    }
                    FormSectionCard(title: "密钥") {
                        LabeledField(label: "API Key") {
                            HStack(spacing: 8) {
                                if showKey {
                                    LeadingTextField(text: $apiKey, monospaced: true)
                                } else {
                                    LeadingSecureField(text: $apiKey, monospaced: true)
                                }
                                Button {
                                    showKey.toggle()
                                } label: {
                                    Image(systemName: showKey ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    FormSectionCard(title: "模型") {
                        ForEach(models.indices, id: \.self) { index in
                            HStack(spacing: 8) {
                                LeadingTextField(text: $models[index], monospaced: true)
                                Button {
                                    _ = models.remove(at: index)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        HStack(spacing: 14) {
                            Button {
                                models.append("")
                            } label: {
                                Label("添加模型", systemImage: "plus")
                            }
                            Button {
                                fetchModels()
                            } label: {
                                if isFetchingModels {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("获取中…")
                                    }
                                } else {
                                    Label("自动获取模型", systemImage: "arrow.down.circle")
                                }
                            }
                            .disabled(isFetchingModels)
                        }
                        if let message = fetchMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(fetchFailed ? Color.red : Color.green)
                        }
                    }
                    if let error = validationError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }

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
        .frame(width: 520, height: 600)
    }

    /// 请求该密钥的模型列表接口，把返回的模型 id 去重后合并进列表。
    private func fetchModels() {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespaces)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard !trimmedBaseURL.isEmpty, !trimmedKey.isEmpty else {
            fetchFailed = true
            fetchMessage = "请先填写 BaseURL 和 API Key"
            return
        }

        isFetchingModels = true
        fetchMessage = nil
        Task {
            do {
                let ids = try await APIKeyTester.fetchModelIDs(baseURL: trimmedBaseURL, apiKey: trimmedKey)
                let existing = Set(models.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                let fresh = ids.filter { !existing.contains($0) }
                models = models.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } + fresh
                fetchFailed = false
                fetchMessage = fresh.isEmpty
                    ? "没有新增：服务端返回 \(ids.count) 个模型，均已存在"
                    : "已添加 \(fresh.count) 个模型（服务端共 \(ids.count) 个）"
            } catch {
                fetchFailed = true
                fetchMessage = "获取失败：\(error.localizedDescription)"
            }
            isFetchingModels = false
        }
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
