import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    var body: some View {
        SettingsDashboardView()
            .frame(width: 900, height: 650)
    }
}

struct SettingsDashboardView: View {
    @Environment(WorkbenchStore.self) private var store
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @AppStorage("showCompletedTasks") private var showCompletedTasks = true

    @State private var apiKey = ""
    @State private var revealAPIKey = false
    @State private var apiStatus = "API Key 只保存在这台 Mac 的钥匙串中。"
    @State private var syncKey = ""
    @State private var revealSyncKey = false
    @State private var syncStatus = "尚未连接跨平台同步"
    @State private var isSyncing = false
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = WorkbenchBackupDocument()
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeading(
                    eyebrow: "SETTINGS",
                    title: "设置",
                    subtitle: "AI、跨平台同步和本机数据，都在这里管理。"
                )

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    generalCard
                    deepSeekCard
                    syncCard
                    dataCard
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .onAppear {
            apiKey = KeychainStore.readDeepSeekKey()
            syncKey = KeychainStore.readSyncKey()
            if !syncKey.isEmpty { syncStatus = "同步码已保存在钥匙串，可点击立即同步" }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Data(contentsOf: url))
            } catch { errorMessage = error.localizedDescription }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "西瓜老师工作台备份"
        ) { result in
            if case .failure(let error) = result { errorMessage = error.localizedDescription }
        }
        .alert("操作没有完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "未知错误") }
    }

    private var generalCard: some View {
        settingCard(eyebrow: "GENERAL", title: "工作台偏好", tint: WorkbenchTheme.paperLight) {
            LabeledContent("外观", value: "西瓜老师品牌浅色")
            Toggle("每周从星期一开始", isOn: $weekStartsMonday)
            Toggle("显示已完成任务", isOn: $showCompletedTasks)
        }
    }

    private var deepSeekCard: some View {
        settingCard(eyebrow: "AI CONNECTION", title: "DeepSeek API Key", tint: WorkbenchTheme.sage) {
            Text("用于智能安排、回声日记和本周简报，不会进入备份或云同步。")
                .font(.system(size: 12)).foregroundStyle(WorkbenchTheme.muted)
            if revealAPIKey {
                TextField("sk-…", text: $apiKey).textFieldStyle(.roundedBorder)
            } else {
                SecureField("sk-…", text: $apiKey).textFieldStyle(.roundedBorder)
            }
            Toggle("显示密钥", isOn: $revealAPIKey)
            HStack {
                Button("保存到钥匙串") { saveAPIKey() }
                    .buttonStyle(OutlineButtonStyle())
                Button("清除", role: .destructive) {
                    apiKey = ""
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty && KeychainStore.readDeepSeekKey().isEmpty)
            }
            Text(apiStatus).font(.caption).foregroundStyle(WorkbenchTheme.muted)
        }
    }

    private var syncCard: some View {
        settingCard(eyebrow: "CROSS-PLATFORM", title: "跨平台同步", tint: WorkbenchTheme.yellow.opacity(0.7)) {
            Text("在网页端和这台 Mac 填写同一个同步码，任务、月历备注和日记就能合并。")
                .font(.system(size: 12)).foregroundStyle(WorkbenchTheme.muted)
            if revealSyncKey {
                TextField("至少32位同步码", text: $syncKey).textFieldStyle(.roundedBorder)
            } else {
                SecureField("至少32位同步码", text: $syncKey).textFieldStyle(.roundedBorder)
            }
            Toggle("显示同步码", isOn: $revealSyncKey)
            HStack {
                Button(syncKey.isEmpty ? "生成同步码" : "重新生成") { generateSyncKey() }
                    .buttonStyle(OutlineButtonStyle())
                Button {
                    Task { await synchronize() }
                } label: {
                    Text(isSyncing ? "正在同步…" : "立即同步")
                }
                .buttonStyle(SolidButtonStyle(fill: WorkbenchTheme.green))
                .disabled(isSyncing || syncKey.count < 32)
            }
            Text(syncStatus).font(.caption).foregroundStyle(WorkbenchTheme.green)
        }
    }

    private var dataCard: some View {
        settingCard(eyebrow: "LOCAL DATA", title: "备份与维护", tint: WorkbenchTheme.redSoft.opacity(0.65)) {
            Text("备份包含任务、月历备注、日记和回声对话，不包含任何密钥。")
                .font(.system(size: 12)).foregroundStyle(WorkbenchTheme.muted)
            HStack {
                Button("导出备份") {
                    do {
                        exportDocument = WorkbenchBackupDocument(data: try store.exportData())
                        showingExporter = true
                    } catch { errorMessage = error.localizedDescription }
                }
                .buttonStyle(OutlineButtonStyle())
                Button("导入备份") { showingImporter = true }
                    .buttonStyle(OutlineButtonStyle())
            }
            Button("清理所有已完成任务", role: .destructive) { store.deleteCompletedTasks() }
                .disabled(store.completedTasks.isEmpty)
        }
    }

    private func settingCard<Content: View>(
        eyebrow: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow).font(.system(size: 10, weight: .heavy)).tracking(1.5).foregroundStyle(WorkbenchTheme.green)
            Text(title).font(WorkbenchTheme.displayFont(24))
            content()
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
        .hardCard(fill: tint, radius: 18, shadow: 6, padding: 20)
    }

    private func saveAPIKey() {
        do {
            try KeychainStore.saveDeepSeekKey(apiKey)
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            apiStatus = apiKey.isEmpty ? "DeepSeek API Key 已清除。" : "DeepSeek API Key 已安全保存。"
        } catch { apiStatus = error.localizedDescription }
    }

    private func generateSyncKey() {
        syncKey = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "")
        do {
            try KeychainStore.saveSyncKey(syncKey)
            revealSyncKey = true
            syncStatus = "同步码已生成；请复制到网页端设置页"
        } catch { syncStatus = error.localizedDescription }
    }

    @MainActor
    private func synchronize() async {
        let key = syncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 32 else {
            syncStatus = "请先生成或填写至少32位同步码"
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try KeychainStore.saveSyncKey(key)
            let remote = try await CrossPlatformSyncService.shared.fetch(syncKey: key)
            if let data = remote.stateData { try store.mergeRemoteData(data) }
            let merged = try store.exportData()
            let updatedAt = try await CrossPlatformSyncService.shared.push(
                stateData: merged,
                syncKey: key,
                clientUpdatedAt: remote.updatedAt
            )
            let date = Date(timeIntervalSince1970: updatedAt / 1000)
            syncStatus = "已同步 · \(date.formatted(date: .omitted, time: .shortened))"
            store.notice = "网页与 Mac 工作台已经同步"
        } catch {
            syncStatus = error.localizedDescription
        }
    }
}
