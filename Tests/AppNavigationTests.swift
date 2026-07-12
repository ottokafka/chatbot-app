import XCTest
@testable import DeveloperChatbotCore

// NavigationSplitView column presentation (`preferredCompactColumn`, preferDetail /
// preferSidebar) is **not** unit-tested here: SwiftUI split-view layout has no pure
// non-UI helpers worth extracting, and UI tests for column visibility are out of scope.
// **Manual QA remains the source of truth** for compact column presentation (N1–N10, M*).
// These tests cover only `AppNavigationModel` route / restore behavior.

@MainActor
final class AppNavigationTests: XCTestCase {
    private let lastRouteKey = AppNavigationModel.lastRouteKey
    private let restoreFlagKey = AppNavigationModel.restoreFlagKey

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: lastRouteKey)
        UserDefaults.standard.removeObject(forKey: restoreFlagKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: lastRouteKey)
        UserDefaults.standard.removeObject(forKey: restoreFlagKey)
        super.tearDown()
    }

    func testDefaultRouteIsHome() {
        let nav = AppNavigationModel(defaultRoute: .home)
        XCTAssertEqual(nav.route, .home)
        XCTAssertFalse(nav.restoreLastRouteOnLaunch)
        XCTAssertFalse(nav.didRestoreRouteOnLaunch)
    }

    func testNavigateUpdatesRouteAndPersists() {
        let nav = AppNavigationModel(defaultRoute: .home)
        nav.navigate(to: .flashcards, source: .homeTile)
        XCTAssertEqual(nav.route, .flashcards)
        XCTAssertEqual(UserDefaults.standard.string(forKey: lastRouteKey), AppRoute.flashcards.rawValue)
        XCTAssertEqual(nav.lastTransition?.from, .home)
        XCTAssertEqual(nav.lastTransition?.to, .flashcards)
        XCTAssertEqual(nav.lastTransition?.source, .homeTile)
    }

    func testNavigateSameRouteIsNoOp() {
        let nav = AppNavigationModel(defaultRoute: .chat)
        nav.navigate(to: .flashcards, source: .switcher)
        nav.navigate(to: .flashcards, source: .homeTile)
        XCTAssertEqual(nav.lastTransition?.source, .switcher)
    }

    func testGoHome() {
        let nav = AppNavigationModel(defaultRoute: .lifePath)
        nav.goHome(source: .done)
        XCTAssertEqual(nav.route, .home)
        XCTAssertEqual(nav.lastTransition?.source, .done)
    }

    func testRestoreLastRouteWhenEnabled() {
        UserDefaults.standard.set(true, forKey: restoreFlagKey)
        UserDefaults.standard.set(AppRoute.chat.rawValue, forKey: lastRouteKey)
        let nav = AppNavigationModel(defaultRoute: .home)
        XCTAssertEqual(nav.route, .chat)
        XCTAssertTrue(nav.restoreLastRouteOnLaunch)
        XCTAssertTrue(nav.didRestoreRouteOnLaunch)
        XCTAssertEqual(nav.lastTransition?.source, .coldStart)
        XCTAssertEqual(nav.lastTransition?.to, .chat)
    }

    func testRestoreDisabledIgnoresSavedRoute() {
        UserDefaults.standard.set(false, forKey: restoreFlagKey)
        UserDefaults.standard.set(AppRoute.chat.rawValue, forKey: lastRouteKey)
        let nav = AppNavigationModel(defaultRoute: .home)
        XCTAssertEqual(nav.route, .home)
        XCTAssertFalse(nav.didRestoreRouteOnLaunch)
    }

    func testToggleRestorePersistsFlag() {
        let nav = AppNavigationModel(defaultRoute: .home)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: restoreFlagKey))
        nav.restoreLastRouteOnLaunch = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: restoreFlagKey))
        nav.restoreLastRouteOnLaunch = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: restoreFlagKey))
    }

    func testRestoreWithMissingLastRouteFallsBackToDefault() {
        UserDefaults.standard.set(true, forKey: restoreFlagKey)
        UserDefaults.standard.removeObject(forKey: lastRouteKey)
        let nav = AppNavigationModel(defaultRoute: .home)
        XCTAssertEqual(nav.route, .home)
        XCTAssertFalse(nav.didRestoreRouteOnLaunch)
    }

    func testRestoreWithInvalidLastRouteFallsBackToDefault() {
        UserDefaults.standard.set(true, forKey: restoreFlagKey)
        UserDefaults.standard.set("not-a-route", forKey: lastRouteKey)
        let nav = AppNavigationModel(defaultRoute: .home)
        XCTAssertEqual(nav.route, .home)
        XCTAssertFalse(nav.didRestoreRouteOnLaunch)
    }

    func testPersistCurrentRouteIfNeeded() {
        UserDefaults.standard.set(true, forKey: restoreFlagKey)
        UserDefaults.standard.set(AppRoute.lifePath.rawValue, forKey: lastRouteKey)
        let nav = AppNavigationModel(defaultRoute: .home)
        UserDefaults.standard.removeObject(forKey: lastRouteKey)
        nav.persistCurrentRouteIfNeeded()
        XCTAssertEqual(UserDefaults.standard.string(forKey: lastRouteKey), AppRoute.lifePath.rawValue)
    }
}
