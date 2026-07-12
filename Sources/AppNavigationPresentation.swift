import SwiftUI

/// Compact-column presentation policy for `NavigationSplitView`.
/// UI-owned only — keep out of `AppNavigationModel` (route model stays pure).
///
/// Intended consumers are **iOS compact** call sites (`ContentView` helpers). The type is
/// available on macOS because `NavigationSplitViewColumn` is cross-platform, but production
/// writes are compile-time gated with `#if os(iOS)` so macOS never binds column state.
@MainActor
enum AppNavigationPresentation {
    static func preferDetail(column: Binding<NavigationSplitViewColumn>) {
        column.wrappedValue = .detail
    }

    static func preferSidebar(column: Binding<NavigationSplitViewColumn>) {
        column.wrappedValue = .sidebar
    }
}
