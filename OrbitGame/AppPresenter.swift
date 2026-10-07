import UIKit

enum AppPresenter {
    @MainActor
    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
    }

    @MainActor
    static func rootViewController() -> UIViewController? {
        keyWindow()?.rootViewController
    }

    @MainActor
    static func topViewController() -> UIViewController? {
        topViewController(from: rootViewController())
    }

    @MainActor
    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigation = root as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }

        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }

        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }

        return root
    }
}
