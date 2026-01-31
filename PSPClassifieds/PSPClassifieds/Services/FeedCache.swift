import Foundation

/// Lightweight cache for feed posts to enable instant display on app launch
actor FeedCache {
    static let shared = FeedCache()
    
    private let fileManager = FileManager.default
    private let maxCachedPosts = 50
    
    private var cacheDirectory: URL? {
        fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("FeedCache", isDirectory: true)
    }
    
    private init() {
        createCacheDirectoryIfNeeded()
    }
    
    private func createCacheDirectoryIfNeeded() {
        guard let cacheDir = cacheDirectory else { return }
        if !fileManager.fileExists(atPath: cacheDir.path) {
            try? fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }
    
    private func cacheFileURL(for category: Category) -> URL? {
        let categoryName = category == .all ? "all" : category.rawValue
        return cacheDirectory?.appendingPathComponent("feed_\(categoryName).json")
    }
    
    // MARK: - Public API
    
    func cachePosts(_ posts: [Post], for category: Category) {
        guard let fileURL = cacheFileURL(for: category) else { return }
        
        let postsToCache = Array(posts.prefix(maxCachedPosts))
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(postsToCache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("FeedCache: Failed to cache posts - \(error)")
        }
    }
    
    func loadCachedPosts(for category: Category) -> [Post] {
        guard let fileURL = cacheFileURL(for: category),
              fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Post].self, from: data)
        } catch {
            print("FeedCache: Failed to load cached posts - \(error)")
            return []
        }
    }
    
    func clearCache() {
        guard let cacheDir = cacheDirectory else { return }
        try? fileManager.removeItem(at: cacheDir)
        createCacheDirectoryIfNeeded()
    }
}
