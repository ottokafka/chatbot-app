import SwiftUI
// Xcode monorepo target compiles Sources as one module (no DeveloperChatbotCore).
// SPM uses App/App.swift which imports DeveloperChatbotCore instead.
#if canImport(DeveloperChatbotCore)
import DeveloperChatbotCore
#endif

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

@main
struct DeveloperChatbotApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
