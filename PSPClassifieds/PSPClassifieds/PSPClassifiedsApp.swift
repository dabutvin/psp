import SwiftUI
import SwiftData
import UIKit

// MARK: - App Delegate for Push Notifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Register background fetch task early in app lifecycle
        BackgroundFetchManager.shared.registerBackgroundTask()
        return true
    }
    
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }
    
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
}

// MARK: - Main App

@main
struct PSPClassifiedsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthManager()
    @StateObject private var notificationManager = NotificationManager.shared
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
                .environmentObject(notificationManager)
                .environment(savedPostsManager)
                .modelContainer(sharedModelContainer)
                .onAppear {
                    savedPostsManager.configure(with: sharedModelContainer.mainContext)
                    // Schedule background refresh when app becomes active
                    BackgroundFetchManager.shared.scheduleAppRefresh()
                    // Clear badge when app opens
                    notificationManager.clearBadge()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var selectedTab = 0
    @State private var postToOpen: Post?
    /// A shared link can land on the login screen, so hold the post until the
    /// user is through it.
    @State private var postIdAwaitingLogin: Int?
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView(selectedTab: $selectedTab, postToOpen: $postToOpen)
            } else {
                LoginView()
            }
        }
        .onAppear {
            authManager.checkLoginStatus()
        }
        .task {
            // Request notification permission after login
            if authManager.isAuthenticated {
                await notificationManager.requestAuthorization()
            }
        }
        .onOpenURL { url in
            // Universal link from a shared post
            guard let postId = PostLink.postId(from: url) else { return }
            open(postId: postId)
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task {
                    await notificationManager.requestAuthorization()
                }
                
                if let postId = postIdAwaitingLogin {
                    open(postId: postId)
                }
            } else {
                // Reset navigation state on logout
                selectedTab = 0
                postToOpen = nil
                postIdAwaitingLogin = nil
            }
        }
        .onChange(of: notificationManager.pendingPostId) { _, postId in
            guard let postId = postId else { return }
            notificationManager.pendingPostId = nil
            open(postId: postId)
        }
    }
    
    /// Load a post by id and hand it to the feed, which navigates to its detail.
    private func open(postId: Int) {
        guard authManager.isAuthenticated else {
            postIdAwaitingLogin = postId
            return
        }
        
        postIdAwaitingLogin = nil
        
        Task { @MainActor in
            if let post = try? await APIClient.shared.getPost(id: postId) {
                selectedTab = 0
                postToOpen = post
            }
        }
    }
}
