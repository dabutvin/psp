import Foundation
import UserNotifications
import UIKit
import os

private let logger = Logger(subsystem: "com.psp.classifieds", category: "Notifications")

/// Manages push notification registration and handling
@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    /// Current authorization status
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    
    /// The current device token (hex string)
    @Published private(set) var deviceToken: String?
    
    /// Post ID to navigate to (set when notification is tapped)
    @Published var pendingPostId: Int?
    
    /// User's hashtag filter preferences for notifications
    @Published var hashtagFilters: [String]? {
        didSet {
            if oldValue != hashtagFilters {
                Task { await updateDeviceRegistration() }
            }
        }
    }
    
    /// Whether notifications are enabled
    @Published var notificationsEnabled: Bool = true {
        didSet {
            if oldValue != notificationsEnabled {
                Task { await updateDeviceRegistration() }
            }
        }
    }
    
    private let api = APIClient.shared
    
    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    // MARK: - Public Methods
    
    /// Request notification permission and register for remote notifications
    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            
            logger.info("Notification authorization: \(granted ? "granted" : "denied")")
            
            await checkAuthorizationStatus()
            
            if granted {
                // Register for remote notifications on the main thread
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
        
        // Register with our server
        Task {
            await registerDeviceWithServer(token: tokenString)
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
    
    // MARK: - Private Methods
    
    private func registerDeviceWithServer(token: String) async {
        do {
            try await api.registerDevice(
                token: token,
                hashtagFilters: hashtagFilters
            )
            logger.info("Device registered with server")
        } catch {
            logger.error("Failed to register device with server: \(error.localizedDescription)")
        }
    }
    
    private func updateDeviceRegistration() async {
        guard let token = deviceToken else { return }
        
        do {
            try await api.updateDevice(
                token: token,
                hashtagFilters: hashtagFilters,
                enabled: notificationsEnabled
            )
            logger.info("Device registration updated")
        } catch {
            logger.error("Failed to update device registration: \(error.localizedDescription)")
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        logger.info("Received notification in foreground")
        // Show banner even when app is open
        return [.banner, .sound, .badge]
    }
    
    /// Handle notification tap
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        logger.info("Notification tapped: \(userInfo)")
        
        // Extract post ID from notification payload
        if let postId = userInfo["post_id"] as? Int {
            await MainActor.run {
                self.pendingPostId = postId
            }
            logger.info("Set pending post ID: \(postId)")
        }
    }
}
