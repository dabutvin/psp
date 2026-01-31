import SwiftUI
import SwiftData

@main
struct PSPClassifiedsApp: App {
    @StateObject private var authManager = AuthManager()
    @State private var savedPostsManager = SavedPostsManager()
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SavedPost.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environment(savedPostsManager)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    savedPostsManager.configure(with: sharedModelContainer.mainContext)
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .onAppear {
            authManager.checkLoginStatus()
        }
    }
}
