import SwiftUI
import UniformTypeIdentifiers

struct WorkbenchBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(WorkbenchStore.self) private var store
    @AppStorage("weekStartsMonday") private var weekStartsMonday = true
    @AppStorage("showCompletedTasks") private var showCompletedTasks = true
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = WorkbenchBackupDocument()
    @State private var errorMessage: String?

    var body: some View {
        TabView {
            Form {
                LabeledContent("外观", value: "西瓜老师品牌浅色")
                Toggle("每周从星期一开始", isOn: $weekStartsMonday)
                Toggle("显示已完成任务", isOn: $showCompletedTasks)
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gear") }

            Form {
                Section("备份") {
                    Button("导出 JSON 备份…") {
                        do {
                            exportDocument = WorkbenchBackupDocument(data: try store.exportData())
                            showingExporter = true
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    Button("导入网页或原生版备份…") {
                        showingImporter = true
                    }
                    Text("原生版兼容现有网页工作台导出的 JSON 数据。文件只在你选择后读取。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("维护") {
                    Button("清理已完成任务", role: .destructive) {
                        store.deleteCompletedTasks()
                    }
                    .disabled(store.completedTasks.isEmpty)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("数据", systemImage: "externaldrive") }

            VStack(spacing: 14) {
                Image(systemName: "watermelon")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.workbenchGreen)
                Text("西瓜老师工作台")
                    .font(.title2.weight(.semibold))
                Text("原生 macOS 版 · 1.0.0")
                    .foregroundStyle(.secondary)
                Text("把重要的事放在眼前，也给生活留一点回声。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 360)
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try store.importData(Data(contentsOf: url))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "西瓜老师工作台备份"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("操作没有完成", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }
}
