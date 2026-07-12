import SwiftUI

/// Compact-column presentation policy for `NavigationSplitView`.
/// UI-owned only — keep out of `AppNavigationModel` (route model stays pure).
@MainActor
enum AppNavigationPresentation {
    static func preferDetail(column: Binding<NavigationSplitViewColumn>) {
        column.wrappedValue = .detail
    }

    static func preferSidebar(column: Binding<NavigationSplitViewColumn>) {
        column.wrappedValue = .sidebar
    }
}
