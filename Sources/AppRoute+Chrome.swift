import SwiftUI

/// Shared titles and SF Symbols for top-level `AppRoute` (sidebar + compact Apps Menu).
enum AppRouteChrome {
    static func title(_ route: AppRoute, lang: AppLanguage, dueCount: Int? = nil) -> String {
        switch route {
        case .home:
            return L10n.home(lang)
        case .lifePath:
            return L10n.lifePathTitle(lang)
        case .flashcards:
            if let due = dueCount {
                return L10n.flashcardsWithDue(lang, due: due)
            }
            return L10n.flashcards(lang)
        case .chat:
            return L10n.conversations(lang)
        }
    }

    static func systemImage(_ route: AppRoute) -> String {
        switch route {
        case .home:
            return "square.grid.2x2"
        case .lifePath:
            return "figure.and.child.holdinghands"
        case .flashcards:
            return "rectangle.on.rectangle.angled"
        case .chat:
            return "bubble.left.and.bubble.right"
        }
    }
}

/// iOS compact: leading sidebar reveal + trailing Apps Menu over every feature shell.
/// macOS / regular width: no-op (sidebar remains the primary switcher).
///
/// `extraTrailing` is rendered after the Apps Menu (e.g. `ChatToolsMenuButton`).
struct CompactFeatureChrome<ExtraTrailing: View>: ViewModifier {
    @ObservedObject var nav: AppNavigationModel
    var lang: AppLanguage
    var dueCount: Int
    var onPreferSidebar: () -> Void
    /// When false, only the Apps Menu is added (e.g. Life Path already owns leading).
    var showSidebarButton: Bool
    @ViewBuilder var extraTrailing: () -> ExtraTrailing

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar {
            if isCompact {
                if showSidebarButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            onPreferSidebar()
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel(L10n.showSidebar(lang))
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    appsMenu
                    extraTrailing()
                }
            }
        }
        #else
        content
        #endif
    }

    #if os(iOS)
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    private var appsMenu: some View {
        Menu {
            ForEach(AppRoute.allCases) { route in
                Button {
                    if nav.route != route {
                        nav.navigate(to: route, source: .switcher)
                    }
                } label: {
                    Label {
                        HStack {
                            Text(
                                AppRouteChrome.title(
                                    route,
                                    lang: lang,
                                    dueCount: route == .flashcards ? dueCount : nil
                                )
                            )
                            if nav.route == route {
                                Image(systemName: "checkmark")
                            }
                        }
                    } icon: {
                        Image(systemName: AppRouteChrome.systemImage(route))
                    }
                }
            }
        } label: {
            // Distinct from ChatToolsMenuButton (`square.grid.2x2`) when co-located on compact chat.
            Label(L10n.appsSection(lang), systemImage: "square.grid.3x2")
        }
        .accessibilityLabel(L10n.appsMenu(lang))
    }
    #endif
}

extension View {
    /// Injects compact iOS Apps Menu + optional sidebar button. No-op on macOS.
    func compactFeatureChrome(
        nav: AppNavigationModel,
        lang: AppLanguage,
        dueCount: Int,
        onPreferSidebar: @escaping () -> Void,
        showSidebarButton: Bool = true
    ) -> some View {
        modifier(
            CompactFeatureChrome(
                nav: nav,
                lang: lang,
                dueCount: dueCount,
                onPreferSidebar: onPreferSidebar,
                showSidebarButton: showSidebarButton,
                extraTrailing: { EmptyView() }
            )
        )
    }

    /// Same as `compactFeatureChrome`, with additional trailing controls after the Apps Menu.
    func compactFeatureChrome<ExtraTrailing: View>(
        nav: AppNavigationModel,
        lang: AppLanguage,
        dueCount: Int,
        onPreferSidebar: @escaping () -> Void,
        showSidebarButton: Bool = true,
        @ViewBuilder extraTrailing: @escaping () -> ExtraTrailing
    ) -> some View {
        modifier(
            CompactFeatureChrome(
                nav: nav,
                lang: lang,
                dueCount: dueCount,
                onPreferSidebar: onPreferSidebar,
                showSidebarButton: showSidebarButton,
                extraTrailing: extraTrailing
            )
        )
    }
}
