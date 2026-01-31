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
    
    // Filters
    var filterHashtags: [String] = []
    var filterSinceDate: Date? = nil
    
    var hasActiveFilters: Bool {
        !filterHashtags.isEmpty || filterSinceDate != nil
    }
    
    var activeFilterCount: Int {
        var count = filterHashtags.count
        if filterSinceDate != nil { count += 1 }
        return count
    }
    
    private var nextCursor: String? = nil
    private let api = APIClient.shared
    
    // MARK: - Public Methods
    
    func loadInitialPosts() async {
        guard posts.isEmpty else { return }
        await refresh()
    }
    
    /// Combines category hashtag with filter hashtags into a single list
    private var allHashtags: [String]? {
        var hashtags = filterHashtags
        if let categoryHashtag = selectedCategory.hashtag {
            hashtags.insert(categoryHashtag, at: 0)
        }
        return hashtags.isEmpty ? nil : hashtags
    }
    
    func refresh() async {
        isRefreshing = true
        error = nil
        nextCursor = nil
        hasMore = true
        
        do {
            let response = try await api.getPosts(
                hashtags: allHashtags,
                since: filterSinceDate,
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
                hashtags: allHashtags,
                since: filterSinceDate,
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
    
    func applyFilters(hashtags: Set<String>, sinceDate: Date?) async {
        filterHashtags = Array(hashtags)
        filterSinceDate = sinceDate
        posts = []
        await refresh()
    }
    
    func clearFilters() async {
        filterHashtags = []
        filterSinceDate = nil
        posts = []
        await refresh()
    }
    
    func removeHashtagFilter(_ hashtag: String) async {
        filterHashtags.removeAll { $0 == hashtag }
        posts = []
        await refresh()
    }
    
    func clearDateFilter() async {
        filterSinceDate = nil
        posts = []
        await refresh()
    }
    
    func shouldLoadMore(currentPost: Post) -> Bool {
        guard let index = posts.firstIndex(of: currentPost) else { return false }
        return index >= posts.count - 3
    }
}
