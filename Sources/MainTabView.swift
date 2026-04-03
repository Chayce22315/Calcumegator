import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            CalculatorView()
                .tabItem {
                    Label("Calculator", systemImage: "square.grid.3x3.fill")
                }

            HomeworkAIView()
                .tabItem {
                    Label("Homework", systemImage: "sparkles")
                }
        }
    }
}

#Preview {
    MainTabView()
        .preferredColorScheme(.dark)
}
