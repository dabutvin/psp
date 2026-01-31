import Foundation

@MainActor
@Observable
class FeedViewModel {
    var posts: [Post] = []
    var isLoading = false
    var isRefreshing = false
    var hasMore = true
    var error: Error?
    var selectedCategory: Category = .all
    
    private var nextCursor: String? = nil
    private let api = APIClient.shared
    
    // MARK: - Public Methods
    
    func loadInitialPosts() async {
        guard posts.isEmpty else { return }
        await refresh()
    }
    
    func refresh() async {
        isRefreshing = true
        error = nil
        nextCursor = nil
        hasMore = true
        
        do {
            let response = try await api.getPosts(
                hashtag: selectedCategory.hashtag,
                limit: 20,
                cursor: nil
            )
            
            posts = response.messages
            nextCursor = response.nextCursor
            hasMore = response.hasMore
        } catch {
            self.error = error
        }
        
        isRefreshing = false
    }
    
    func loadMore() async {
        guard !isLoading, hasMore else { return }
        
        isLoading = true
        
        do {
            let response = try await api.getPosts(
                hashtag: selectedCategory.hashtag,
                limit: 20,
                cursor: nextCursor
            )
            
            posts.append(contentsOf: response.messages)
            nextCursor = response.nextCursor
            hasMore = response.hasMore
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    func changeCategory(_ category: Category) async {
        guard category != selectedCategory else { return }
        selectedCategory = category
        posts = []
        await refresh()
    }
    
    func shouldLoadMore(currentPost: Post) -> Bool {
        guard let index = posts.firstIndex(of: currentPost) else { return false }
        return index >= posts.count - 3
    }
}
