import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 内容区是刻意的浅色工作室风格，统一外观避免半深半浅。
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct MQ80StudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window(AppConstants.appName, id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 1060, minHeight: 720)
                .preferredColorScheme(.light)
                .background(WindowConfigurator())
        }
        .defaultSize(width: 1240, height: 820)
        .windowStyle(.hiddenTitleBar)
    }
}
