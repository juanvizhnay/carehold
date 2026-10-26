import Data
import DesignSystem
import SwiftUI
import UIKit

@main
struct CareHoldApp: App {
    // Composition root: the only place that builds the Data layer.
    private let backend = Backend(config: AppConfig.backend)

    init() {
        Self.applyWarmChrome()
    }

    var body: some Scene {
        WindowGroup {
            RootView(backend: backend)
        }
    }

    /// Opaque vanilla bars with a hairline, so the whole app sits on the same warm paper.
    private static func applyWarmChrome() {
        let background = UIColor(DS.Colors.background)
        let hairline = UIColor(DS.Colors.hairline)
        let ink = UIColor(DS.Colors.textPrimary)

        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = background
        tabBar.shadowColor = hairline
        UITabBar.appearance().standardAppearance = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        let navigationBar = UINavigationBarAppearance()
        navigationBar.configureWithOpaqueBackground()
        navigationBar.backgroundColor = background
        navigationBar.shadowColor = .clear
        let rounded = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle)
            .withDesign(.rounded)?.withSymbolicTraits(.traitBold)
        if let rounded {
            navigationBar.largeTitleTextAttributes = [.foregroundColor: ink, .font: UIFont(descriptor: rounded, size: 0)]
        }
        let inline = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .headline).withDesign(.rounded)
        if let inline {
            navigationBar.titleTextAttributes = [.foregroundColor: ink, .font: UIFont(descriptor: inline, size: 0)]
        }
        UINavigationBar.appearance().standardAppearance = navigationBar
        UINavigationBar.appearance().scrollEdgeAppearance = navigationBar
        UINavigationBar.appearance().compactAppearance = navigationBar
    }
}
