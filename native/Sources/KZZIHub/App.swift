import SwiftUI

struct KZZIHubApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1080, minHeight: 720)
                .tint(Theme.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("键盘") {
                Button("读取配置") { Task { await model.refreshConfig() } }
                    .keyboardShortcut("r", modifiers: .command)
                Button("保存到键盘") { Task { await model.saveToDevice() } }
                    .keyboardShortcut("s", modifiers: .command)
                Button("重新连接") { Task { await model.reconnect() } }
                Divider()
                Button("打开输入监控设置") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }
}
