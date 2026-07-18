import Foundation
import Combine

/// Top-level app destinations. Owned by `AppNavigationModel` (window-scoped).
enum AppRoute: String, CaseIterable, Identifiable, Codable {
    case home
    case lifePath
    case flashcards
    case chat
    case songGen

    var id: String { rawValue }
}

/// How a route change was requested (logging / analytics).
enum AppNavigationSource: String {
    case coldStart
    case homeTile
    case switcher
    case done
    case programmatic
}

/// Single choke-point for top-level navigation. Mutate only via `navigate(to:source:)`.
@MainActor
final class AppNavigationModel: ObservableObject {
    /// Mutate only via `navigate(to:source:)`.
    @Published private(set) var route: AppRoute

    /// When true, next cold start opens the last navigated route instead of `defaultRoute`.
    @Published var restoreLastRouteOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(restoreLastRouteOnLaunch, forKey: Self.restoreFlagKey)
        }
    }

    /// True when this instance opened a restored route (not the default) on init.
    private(set) var didRestoreRouteOnLaunch: Bool = false

    /// Last transition for root `onChange` / logging.
    private(set) var lastTransition: (from: AppRoute, to: AppRoute, source: AppNavigationSource)?

    static let lastRouteKey = "app.navigation.lastRoute.v1"
    static let restoreFlagKey = "app.navigation.restoreLastRoute.v1"

    /// - Parameter defaultRoute: `.home` for product ship; use `.chat` only for behavior-neutral experiments.
    init(defaultRoute: AppRoute = .home) {
        let restore = UserDefaults.standard.bool(forKey: Self.restoreFlagKey)
        self.restoreLastRouteOnLaunch = restore

        if restore,
           let raw = UserDefaults.standard.string(forKey: Self.lastRouteKey),
           let saved = AppRoute(rawValue: raw) {
            route = saved
            didRestoreRouteOnLaunch = saved != defaultRoute
            if didRestoreRouteOnLaunch {
                lastTransition = (defaultRoute, saved, .coldStart)
            }
        } else {
            route = defaultRoute
            didRestoreRouteOnLaunch = false
        }
    }

    func navigate(to newRoute: AppRoute, source: AppNavigationSource) {
        guard newRoute != route else { return }
        let from = route
        route = newRoute
        UserDefaults.standard.set(newRoute.rawValue, forKey: Self.lastRouteKey)
        lastTransition = (from, newRoute, source)
    }

    func goHome(source: AppNavigationSource = .done) {
        navigate(to: .home, source: source)
    }

    /// Persists the current route so a future restore can return here.
    /// Call after cold-start restore so even if the user never navigates again, the flag stays meaningful.
    func persistCurrentRouteIfNeeded() {
        UserDefaults.standard.set(route.rawValue, forKey: Self.lastRouteKey)
    }
}
