import SwiftUI

struct MainTabView: View {
    @Environment(SavedPostsManager.self) private var savedPostsManager
    @Binding var selectedTab: Int
    @Binding var postFromNotification: Post?
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MainFeedView(postFromNotification: $postFromNotification)
                .tabItem {
                    Label("Browse", systemImage: "list.bullet")
                }
                .tag(0)
            
            SavedPostsView()
                .tabItem {
                    Label("Saved", systemImage: "bookmark.fill")
                }
                .tag(1)
            
            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    MainTabView(selectedTab: .constant(0), postFromNotification: .constant(nil))
        .environment(SavedPostsManager())
}
