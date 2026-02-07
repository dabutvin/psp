import Foundation
import BackgroundTasks
import os

private let logger = Logger(subsystem: "com.psp.classifieds", category: "BackgroundFetch")

/// Manages background refresh of feed data for offline browsing
class BackgroundFetchManager {
    static let shared = BackgroundFetchManager()
    
    static let taskIdentifier = "com.psp.classifieds.refresh"
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register the background task with the system. Call this early in app launch.
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        logger.info("Background refresh task registered")
    }
    
    // MARK: - Scheduling
    
    /// Schedule the next background refresh. Call after each refresh completes.
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        // Request to run no earlier than 15 minutes from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background refresh scheduled for ~15 minutes from now")
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Task Handling
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        logger.info("Background refresh task started")
        
        // Schedule the next refresh
        scheduleAppRefresh()
        
        // Create a task to fetch posts
        let fetchTask = Task {
            do {
                let api = APIClient.shared
                let cache = FeedCache.shared
                
                logger.info("Fetching posts in background...")
                let response = try await api.getPosts(limit: 50)
                
                logger.info("Caching \(response.messages.count) posts")
                await cache.cachePosts(response.messages, for: .all)
                
                logger.info("Background refresh completed successfully")
                task.setTaskCompleted(success: true)
            } catch {
                logger.error("Background refresh failed: \(error.localizedDescription)")
                task.setTaskCompleted(success: false)
            }
        }
        
        // Handle task expiration
        task.expirationHandler = {
            logger.warning("Background refresh task expired")
            fetchTask.cancel()
        }
    }
}
