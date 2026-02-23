import Foundation
import UserNotifications
import UIKit
import os

private let logger = Logger(subsystem: "com.psp.classifieds", category: "Notifications")

/// Manages push notification registration, subscriptions, and handling
@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    // MARK: - Published Properties
    
    /// Current authorization status
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// The current device token (hex string)
    @Published private(set) var deviceToken: String?
    
    /// Post ID to navigate to (set when notification is tapped)
    @Published var pendingPostId: Int?
    
    /// Search terms the user is subscribed to
    @Published private(set) var searchFilters: [String] = []
    
    /// Whether to notify for ALL new posts
    @Published private(set) var notifyAll: Bool = false
    
    /// Whether to receive summary notifications instead of individual ones
    @Published private(set) var notifySummary: Bool = false
    
    /// Master on/off switch for notifications
    @Published private(set) var notificationsEnabled: Bool = true
    
    /// Whether we're currently syncing with the server
    @Published private(set) var isSyncing: Bool = false
    
    // MARK: - Private Properties
    
    private let api = APIClient.shared
    private let userDefaultsKeySearchFilters = "notification_search_filters"
    private let userDefaultsKeyNotifyAll = "notification_notify_all"
    private let userDefaultsKeyNotifySummary = "notification_notify_summary"
    private let userDefaultsKeyEnabled = "notification_enabled"
    
    // MARK: - Initialization
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        loadFromLocal()
    }
    
    // MARK: - Public Methods: Authorization
    
    /// Request notification permission and register for remote notifications
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            logger.info("Notification authorization: \(granted ? "granted" : "denied")")
            
            await checkAuthorizationStatus()
            
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
        }
    }
    
    /// Check current authorization status
    func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        logger.debug("Authorization status: \(String(describing: settings.authorizationStatus.rawValue))")
    }
    
    /// Called when APNs registration succeeds
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = tokenString
        logger.info("Registered for remote notifications: \(tokenString.prefix(8))...")
        
        Task {
            await registerDeviceWithServer(token: tokenString)
            await fetchFromServer()
        }
    }
    
    /// Called when APNs registration fails
    func didFailToRegisterForRemoteNotifications(error: Error) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    /// Clear the badge count
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                logger.error("Failed to clear badge: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Public Methods: Subscription Management
    
    /// Subscribe to a search term
    func subscribeToSearchTerm(_ term: String) async {
        // Check notification permission first
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
        
        guard authorizationStatus == .authorized else {
            logger.warning("Cannot subscribe: notifications not authorized")
            return
        }
        
        let normalized = term.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalized.isEmpty else { return }
        guard !searchFilters.contains(normalized) else {
            logger.debug("Already subscribed to '\(normalized)'")
            return
        }
        
        searchFilters.append(normalized)
        persistLocally()
        await syncWithServer()
    }
    
    /// Unsubscribe from a search term
    func unsubscribeFromSearchTerm(_ term: String) async {
        let normalized = term.trimmingCharacters(in: .whitespaces).lowercased()
        searchFilters.removeAll { $0 == normalized }
        persistLocally()
        await syncWithServer()
    }
    
    /// Check if subscribed to a search term
    func isSubscribed(to term: String) -> Bool {
        let normalized = term.trimmingCharacters(in: .whitespaces).lowercased()
        return searchFilters.contains(normalized)
    }
    
    /// Set whether to notify for all posts
    func setNotifyAll(_ value: Bool) async {
        guard notifyAll != value else { return }
        notifyAll = value
        persistLocally()
        await syncWithServer()
    }
    
    /// Set whether to receive summary notifications
    func setNotifySummary(_ value: Bool) async {
        guard notifySummary != value else { return }
        notifySummary = value
        persistLocally()
        await syncWithServer()
    }
    
    /// Set master notifications enabled/disabled
    func setNotificationsEnabled(_ value: Bool) async {
        guard notificationsEnabled != value else { return }
        notificationsEnabled = value
        persistLocally()
        await syncWithServer()
    }
    
    // MARK: - Public Methods: Sync
    
    /// Fetch current settings from server and update local state
    func fetchFromServer() async {
        guard let token = deviceToken else {
            logger.debug("No device token, skipping server fetch")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            let device = try await api.getDevice(token: token)
            searchFilters = device.searchFilters ?? []
            notifyAll = device.notifyAll
            notifySummary = device.notifySummary
            notificationsEnabled = device.enabled
            persistLocally()
            logger.info("Fetched device settings from server")
        } catch {
            logger.error("Failed to fetch device settings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Private Methods
    
    private func loadFromLocal() {
        searchFilters = UserDefaults.standard.stringArray(forKey: userDefaultsKeySearchFilters) ?? []
        notifyAll = UserDefaults.standard.bool(forKey: userDefaultsKeyNotifyAll)
        notifySummary = UserDefaults.standard.bool(forKey: userDefaultsKeyNotifySummary)
        notificationsEnabled = UserDefaults.standard.object(forKey: userDefaultsKeyEnabled) as? Bool ?? true
        logger.debug("Loaded from local: \(self.searchFilters.count) filters, notifyAll=\(self.notifyAll), notifySummary=\(self.notifySummary), enabled=\(self.notificationsEnabled)")
    }
    
    private func persistLocally() {
        UserDefaults.standard.set(searchFilters, forKey: userDefaultsKeySearchFilters)
        UserDefaults.standard.set(notifyAll, forKey: userDefaultsKeyNotifyAll)
        UserDefaults.standard.set(notifySummary, forKey: userDefaultsKeyNotifySummary)
        UserDefaults.standard.set(notificationsEnabled, forKey: userDefaultsKeyEnabled)
    }
    
    private func registerDeviceWithServer(token: String) async {
        do {
            try await api.registerDevice(
                token: token,
                searchFilters: searchFilters.isEmpty ? nil : searchFilters,
                notifyAll: notifyAll,
                notifySummary: notifySummary
            )
            logger.info("Device registered with server")
        } catch {
            logger.error("Failed to register device with server: \(error.localizedDescription)")
        }
    }
    
    private var syncTask: Task<Void, Never>?
    private let syncDebounceInterval: TimeInterval = 0.5
    
    private func syncWithServer() async {
        guard let token = deviceToken else {
            logger.debug("No device token, skipping sync")
            return
        }
        
        // Cancel any pending sync and debounce
        syncTask?.cancel()
        
        syncTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(syncDebounceInterval * 1_000_000_000))
            
            guard !Task.isCancelled else { return }
            
            isSyncing = true
            defer { isSyncing = false }
            
            do {
                // Always send searchFilters to sync full state with server
                try await api.updateDevice(
                    token: token,
                    searchFilters: searchFilters,
                    notifyAll: notifyAll,
                    notifySummary: notifySummary,
                    enabled: notificationsEnabled
                )
                logger.info("Device settings synced with server")
            } catch {
                logger.error("Failed to sync with server: \(error.localizedDescription)")
            }
        }
        
        await syncTask?.value
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        logger.info("Received notification in foreground")
        completionHandler([.banner, .sound, .badge])
    }
    
    /// Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        logger.info("Notification tapped: \(userInfo)")
        
        let rawValue = userInfo["post_id"]
        let postId: Int? = (rawValue as? Int) ?? (rawValue as? String).flatMap(Int.init)
        
        if let postId {
            DispatchQueue.main.async {
                self.pendingPostId = postId
                logger.info("Set pending post ID: \(postId)")
            }
        }
        
        completionHandler()
    }
}
