import AppKit
import SwiftUI

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// 列表行与详情标题共用的展示主机名。
func apiKeyDisplayHost(_ key: APIKey) -> String {
    if let url = URL(string: key.baseURL), let host = url.host {
        return host
    }
    return key.baseURL
}

/// API 密钥主区：左列密钥列表（搜索），右侧详情（复制 / 测活 / 官网 / curl）。
struct APIKeysPane: View {
    @EnvironmentObject private var model: APIKeysModel

    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var editorSession: APIKeyEditorSession?
    @State private var keyPendingDelete: APIKey?

    var body: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(width: 320)
            Divider()
            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(item: $editorSession) { session in
            APIKeyEditorSheet(session: session)
        }
        .confirmationDialog(
            "删除密钥 \(keyPendingDelete?.name ?? "")？",
            isPresented: Binding(
                get: { keyPendingDelete != nil },
                set: { if !$0 { keyPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let key = keyPendingDelete {
                    model.delete(key)
                    if selectedID == key.id {
                        selectedID = nil
                    }
                }
                keyPendingDelete = nil
            }
            Button("取消", role: .cancel) { keyPendingDelete = nil }
        } message: {
            Text("将从 apikeys.json 中移除该记录，操作不可撤销。")
        }
    }

    // MARK: - 数据

    private var visibleKeys: [APIKey] {
        guard !searchText.isEmpty else { return model.keys }
        let query = searchText.lowercased()
        return model.keys.filter { key in
            key.name.lowercased().contains(query)
                || key.baseURL.lowercased().contains(query)
                || key.website.lowercased().contains(query)
                || key.models.contains { $0.lowercased().contains(query) }
        }
    }

    // MARK: - 列表列

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                TextField("搜索名称 / 域名 / 模型…", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            Divider()
            List {
                Section("密钥") {
                    ForEach(visibleKeys) { key in
                        keyRow(key)
                    }
                }
            }
            .listStyle(.inset)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    editorSession = APIKeyEditorSession(key: nil)
                } label: {
                    Label("新建 API 密钥", systemImage: "plus")
                }
            }
        }
        .overlay {
            if model.keys.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("还没有 API 密钥\n点右上角 + 添加")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 与主机列表同样的原因（macOS 26 List selection 点击不可靠）：按钮行 + 手动高亮
    private func keyRow(_ key: APIKey) -> some View {
        let isSelected = selectedID == key.id
        return Button {
            selectedID = key.id
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(key.name)
                    .fontWeight(.medium)
                Text(apiKeyDisplayHost(key))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("编辑…") { editorSession = APIKeyEditorSession(key: key) }
            Divider()
            Button("删除…", role: .destructive) { keyPendingDelete = key }
        }
    }

    // MARK: - 详情列

    @ViewBuilder
    private var detailColumn: some View {
        if let id = selectedID,
           let key = model.keys.first(where: { $0.id == id }) {
            APIKeyDetailView(key: key)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "key.horizontal")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("选择一条密钥查看详情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 详情

struct APIKeyDetailView: View {
    @EnvironmentObject private var model: APIKeysModel
    let key: APIKey

    @State private var editorSession: APIKeyEditorSession?
    @State private var confirmDelete = false
    @State private var revealKey = false
    @State private var testOutcome: APIKeyTester.TestOutcome?
    @State private var isTesting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actionRow
                infoSection
                modelsSection
                testSection
                footer
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(key.name)
        .sheet(item: $editorSession) { session in
            APIKeyEditorSheet(session: session)
        }
        .confirmationDialog(
            "删除密钥 \(key.name)？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { model.delete(key) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将从 apikeys.json 中移除该记录，操作不可撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(key.name)
                    .font(.largeTitle.bold())
                Text(apiKeyDisplayHost(key))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button {
                testKey()
            } label: {
                if isTesting {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("测试中…")
                    }
                } else {
                    Label("连通性测试", systemImage: "bolt.horizontal")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isTesting)

            Button {
                copyToPasteboard(APIKeyTester.curlExample(for: key))
            } label: {
                Label("复制 curl 示例", systemImage: "doc.on.doc")
            }

            Spacer()

            Button("编辑…") {
                editorSession = APIKeyEditorSession(key: key)
            }
            Button("删除…", role: .destructive) {
                confirmDelete = true
            }
        }
    }

    private var infoSection: some View {
        section("连接信息") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    keyLabel("BaseURL")
                    HStack {
                        Text(key.baseURL)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        copyButton(key.baseURL)
                    }
                }
                GridRow {
                    keyLabel("API Key")
                    HStack {
                        Text(revealKey ? key.apiKey : APIKeyTester.masked(key.apiKey))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            revealKey.toggle()
                        } label: {
                            Image(systemName: revealKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                        .help(revealKey ? "隐藏" : "显示明文")
                        copyButton(key.apiKey)
                    }
                }
                GridRow {
                    keyLabel("网站")
                    HStack {
                        Text(key.website.isEmpty ? "—" : key.website)
                            .foregroundStyle(key.website.isEmpty ? .secondary : .primary)
                        if !key.website.isEmpty {
                            Button {
                                openWebsite()
                            } label: {
                                Label("打开官网", systemImage: "safari")
                            }
                            .buttonStyle(.borderless)
                            copyButton(key.website)
                        }
                    }
                }
            }
        }
    }

    private var modelsSection: some View {
        section("模型（\(key.models.count)）") {
            if key.models.isEmpty {
                Text("未填写模型")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(key.models, id: \.self) { model in
                        HStack {
                            Text(model)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Spacer()
                            copyButton(model)
                        }
                    }
                }
            }
        }
    }

    private var testSection: some View {
        section("连通性") {
            VStack(alignment: .leading, spacing: 8) {
                if let outcome = testOutcome {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(outcome.isValid ? Color.green : Color.red)
                            .frame(width: 9, height: 9)
                        Text(outcome.message)
                            .foregroundStyle(outcome.isValid ? Color.green : Color.red)
                    }
                } else {
                    Text("测试会请求 \(key.baseURL) 的模型列表接口，验证密钥是否有效。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        Text("创建于 \(key.createdAt.formatted(date: .long, time: .shortened)) · 存储：~/Library/Application Support/SSHManager/apikeys.json（600 权限）")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - 动作

    private func testKey() {
        isTesting = true
        let target = key
        Task.detached {
            let outcome = await APIKeyTester.test(key: target)
            await MainActor.run {
                testOutcome = outcome
                isTesting = false
            }
        }
    }

    private func openWebsite() {
        guard let url = URL(string: key.website), url.scheme != nil else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 小部件

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
    }

    private func keyLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 90, alignment: .leading)
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            copyToPasteboard(text)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help("复制")
    }
}
