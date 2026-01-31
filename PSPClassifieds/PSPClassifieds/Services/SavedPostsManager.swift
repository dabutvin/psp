import Foundation
import SwiftData

@MainActor
@Observable
class SavedPostsManager {
    private var modelContext: ModelContext?
    
    var savedPostIds: Set<Int> = []
    
    func configure(with modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSavedPostIds()
    }
    
    private func loadSavedPostIds() {
        guard let modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<SavedPost>()
            let savedPosts = try modelContext.fetch(descriptor)
            savedPostIds = Set(savedPosts.map { $0.postId })
        } catch {
            print("Failed to load saved post IDs: \(error)")
        }
    }
    
    func isSaved(_ post: Post) -> Bool {
        savedPostIds.contains(post.id)
    }
    
    func isSaved(postId: Int) -> Bool {
        savedPostIds.contains(postId)
    }
    
    func save(_ post: Post) {
        guard let modelContext else { return }
        
        // Check if already saved
        guard !isSaved(post) else { return }
        
        let savedPost = SavedPost(from: post)
        modelContext.insert(savedPost)
        savedPostIds.insert(post.id)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to save post: \(error)")
            modelContext.rollback()
            savedPostIds.remove(post.id)
        }
    }
    
    func unsave(_ post: Post) {
        unsave(postId: post.id)
    }
    
    func unsave(postId: Int) {
        guard let modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<SavedPost>(
                predicate: #Predicate { $0.postId == postId }
            )
            let savedPosts = try modelContext.fetch(descriptor)
            
            for savedPost in savedPosts {
                modelContext.delete(savedPost)
            }
            
            savedPostIds.remove(postId)
            try modelContext.save()
        } catch {
            print("Failed to unsave post: \(error)")
        }
    }
    
    func toggleSaved(_ post: Post) {
        if isSaved(post) {
            unsave(post)
        } else {
            save(post)
        }
    }
    
    func getAllSavedPosts() -> [Post] {
        guard let modelContext else { return [] }
        
        do {
            var descriptor = FetchDescriptor<SavedPost>(
                sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 100
            
            let savedPosts = try modelContext.fetch(descriptor)
            return savedPosts.map { $0.toPost() }
        } catch {
            print("Failed to fetch saved posts: \(error)")
            return []
        }
    }
    
    var savedCount: Int {
        savedPostIds.count
    }
}
