import SwiftUI
#if canImport(DeveloperChatbotCore)
import DeveloperChatbotCore
#endif

@main
struct DeveloperChatbotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
