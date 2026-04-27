//
//  QuickActionHandler.swift
//  epac
//
//  Bridges UIKit Home Screen Quick Actions (UIApplicationShortcutItem) into
//  the SwiftUI navigation layer via NavigationRouter.pendingQuickAction.
//
//  Two entry points:
//  - Cold launch: didFinishLaunchingWithOptions receives the shortcut item and
//    stores it in `coldLaunchAction`; ContentView picks it up on first appear.
//  - Warm launch: performActionFor fires when the app is already running;
//    the action is delivered directly to the router.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Injected by epacApp once ContentView has created the router.
    var router: NavigationRouter? {
        didSet {
            if let action = coldLaunchAction {
                router?.pendingQuickAction = action
                coldLaunchAction = nil
            }
        }
    }

    private var coldLaunchAction: QuickAction?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem,
           let action = QuickAction(rawValue: shortcutItem.type) {
            // Router not wired yet — stash for delivery once ContentView appears.
            coldLaunchAction = action
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let action = QuickAction(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        router?.pendingQuickAction = action
        completionHandler(true)
    }
}
