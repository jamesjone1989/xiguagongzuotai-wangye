import SwiftData
import SwiftUI

@main
struct XiguaWorkbenchApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            WorkbenchTask.self,
            DiaryEntry.self,
            MonthlyNote.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("无法创建本地数据库：\(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WorkbenchRootView()
        }
        .modelContainer(modelContainer)
    }
}
