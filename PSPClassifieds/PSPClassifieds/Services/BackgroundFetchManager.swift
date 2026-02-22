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
        BGTaskScheduler.shared.getPendingTaskRequests { [self] requests in
            let alreadyScheduled = requests.contains { $0.identifier == Self.taskIdentifier }
            if alreadyScheduled {
                logger.debug("Background refresh already scheduled, skipping")
                return
            }
            
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
    }
    
    // MARK: - Task Handling
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        logger.info("Background refresh task started")
        
        // Schedule the next refresh
        scheduleAppRefresh()
        
        // Track completion to prevent calling setTaskCompleted twice
        var isCompleted = false
        let complete: (Bool) -> Void = { success in
            guard !isCompleted else { return }
            isCompleted = true
            task.setTaskCompleted(success: success)
        }
        
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
                complete(true)
            } catch {
                logger.error("Background refresh failed: \(error.localizedDescription)")
                complete(false)
            }
        }
        
        // Handle task expiration
        task.expirationHandler = {
            logger.warning("Background refresh task expired")
            fetchTask.cancel()
            complete(false)
        }
    }
}
