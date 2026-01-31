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
    
    private let baseURL = "http://localhost:8000/api/v1"
    private let session: URLSession
    private let decoder: JSONDecoder
    
    // Toggle for mock data during development
    var useMockData = true
    
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
        search: String? = nil,
        limit: Int = 20,
        cursor: String? = nil
    ) async throws -> PostsResponse {
        if useMockData {
            return MockData.postsResponse
        }
        
        var components = URLComponents(string: "\(baseURL)/messages")!
        var queryItems: [URLQueryItem] = []
        
        if let hashtag = hashtag, !hashtag.isEmpty {
            queryItems.append(URLQueryItem(name: "hashtag", value: hashtag))
        }
        if let search = search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
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
        
        return try await fetch(url: url)
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
