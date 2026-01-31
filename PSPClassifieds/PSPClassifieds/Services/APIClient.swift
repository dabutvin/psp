import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case decodingError(Error)
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()
    
    private let baseURL = "https://psp-api.fly.dev/api/v1"
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Toggle for mock data during development
    var useMockData = false
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Posts
    
    func getPosts(
        hashtag: String? = nil,
        hashtags: [String]? = nil,
        search: String? = nil,
        since: Date? = nil,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> PostsResponse {
        if useMockData {
            // Apply client-side filtering for mock data
            var filtered = MockData.posts
            
            // Filter by category hashtag
            if let hashtag = hashtag, !hashtag.isEmpty {
                filtered = filtered.filter { post in
                    post.hashtags.contains { $0.name.lowercased() == hashtag.lowercased() }
                }
            }
            
            // Filter by additional hashtags
            if let hashtags = hashtags, !hashtags.isEmpty {
                filtered = filtered.filter { post in
                    let postHashtagNames = Set(post.hashtags.map { $0.name.lowercased() })
                    let filterHashtags = Set(hashtags.map { $0.lowercased() })
                    return !postHashtagNames.isDisjoint(with: filterHashtags)
                }
            }
            
            // Filter by date
            if let since = since {
                filtered = filtered.filter { $0.created >= since }
            }
            
            // Filter by search
            if let search = search, !search.isEmpty {
                let query = search.lowercased()
                filtered = filtered.filter { post in
                    post.subject.lowercased().contains(query) ||
                    (post.body?.lowercased().contains(query) ?? false) ||
                    (post.senderName?.lowercased().contains(query) ?? false)
                }
            }
            
            return PostsResponse(messages: filtered, nextCursor: nil, hasMore: false)
        }
        
        var components = URLComponents(string: "\(baseURL)/messages")!
        var queryItems: [URLQueryItem] = []
        
        if let hashtag = hashtag, !hashtag.isEmpty {
            queryItems.append(URLQueryItem(name: "hashtag", value: hashtag))
        }
        if let hashtags = hashtags, !hashtags.isEmpty {
            queryItems.append(URLQueryItem(name: "hashtags", value: hashtags.joined(separator: ",")))
        }
        if let search = search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let since = since {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "since", value: formatter.string(from: since)))
        }
        queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
        if let cursor = cursor {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }
        
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else {
            throw APIError.invalidURL
        }
        
        return try await fetch(url: url)
    }
    
    func getPost(id: Int) async throws -> Post {
        if useMockData {
            if let post = MockData.posts.first(where: { $0.id == id }) {
                return post
            }
            return MockData.posts[0]
        }
        
        guard let url = URL(string: "\(baseURL)/messages/\(id)") else {
            throw APIError.invalidURL
        }
        
        return try await fetch(url: url)
    }
    
    // MARK: - Hashtags
    
    func getHashtags() async throws -> [Hashtag] {
        if useMockData {
            return MockData.hashtags
        }
        
        guard let url = URL(string: "\(baseURL)/hashtags") else {
            throw APIError.invalidURL
        }
        
        let response: HashtagsResponse = try await fetch(url: url)
        return response.hashtags
    }
    
    // MARK: - Private
    
    private func fetch<T: Decodable>(url: URL) async throws -> T {
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.networkError(URLError(.badServerResponse))
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(httpResponse.statusCode)
            }
            
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}
