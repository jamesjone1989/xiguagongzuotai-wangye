import SwiftUI

@main
struct XiguaWorkbenchApp: App {
    @State private var store = WorkbenchStore()
    var body: some Scene {
        WindowGroup("西瓜老师工作台") {
            WorkbenchRootView()
                .environment(store)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            WorkbenchCommands()
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }

}

private struct NewTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct NewDiaryActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newWorkbenchTask: (() -> Void)? {
        get { self[NewTaskActionKey.self] }
        set { self[NewTaskActionKey.self] = newValue }
    }

    var newDiaryEntry: (() -> Void)? {
        get { self[NewDiaryActionKey.self] }
        set { self[NewDiaryActionKey.self] = newValue }
    }
}

struct WorkbenchCommands: Commands {
    @FocusedValue(\.newWorkbenchTask) private var newTask
    @FocusedValue(\.newDiaryEntry) private var newDiary

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("新建任务") { newTask?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(newTask == nil)

            Button("新建日记") { newDiary?() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(newDiary == nil)
        }
    }
}
