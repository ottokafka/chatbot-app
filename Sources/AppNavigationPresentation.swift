import SwiftUI

/// Compact-column presentation policy for `NavigationSplitView`.
/// UI-owned only — keep out of `AppNavigationModel` (route model stays pure).
///
/// Intended consumers are **iOS compact** call sites (`ContentView` helpers). The type is
/// available on macOS because `NavigationSplitViewColumn` is cross-platform, but production
/// writes are compile-time gated with `#if os(iOS)` so macOS never binds column state.
///
/// **Manual QA is the source of truth** for split-view column presentation. These helpers
/// only assign `NavigationSplitViewColumn`; they cannot be unit-tested meaningfully against
/// `NavigationSplitView` layout in this stack (see `AppNavigationTests` header).
@MainActor
enum AppNavigationPresentation {
    /// Prefer the detail column. Optional `onLog` is invoked once per call (lightweight NAV diagnostics).
    static func preferDetail(
        column: Binding<NavigationSplitViewColumn>,
        onLog: ((String) -> Void)? = nil
    ) {
        onLog?("Nav: preferDetail")
        column.wrappedValue = .detail
    }

    /// Prefer the sidebar column. Optional `onLog` is invoked once per call (lightweight NAV diagnostics).
    static func preferSidebar(
        column: Binding<NavigationSplitViewColumn>,
        onLog: ((String) -> Void)? = nil
    ) {
        onLog?("Nav: preferSidebar")
        column.wrappedValue = .sidebar
    }
}
