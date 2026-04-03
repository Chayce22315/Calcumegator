import SwiftUI

// Unsigned app: ship artifacts via GitHub Actions — see README.md and .github/workflows/build.yml.

@main
struct CalcumegatorApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}
