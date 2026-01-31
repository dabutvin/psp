import SwiftUI

struct MainTabView: View {
    @Environment(SavedPostsManager.self) private var savedPostsManager
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainFeedView()
                .tabItem {
                    Label("Browse", systemImage: "list.bullet")
                }
                .tag(0)
            
            SavedPostsView()
                .tabItem {
                    Label("Saved", systemImage: "bookmark.fill")
                }
                .tag(1)
        }
    }
}

#Preview {
    MainTabView()
        .environment(SavedPostsManager())
}
