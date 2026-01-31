import Foundation
import SwiftUI

/// Image loader that includes authentication cookies for groups.parkslopeparents.com
@MainActor
class AuthenticatedImageLoader: ObservableObject {
    @Published var image: UIImage?
    @Published var isLoading = false
    @Published var error: Error?
    
    private var url: URL?
    private var task: Task<Void, Never>?
    
    private static let cache = NSCache<NSURL, UIImage>()
    
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        // Use shared cookie storage - this is where WKWebView cookies are synced
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()
    
    func load(from url: URL?) {
        // Cancel any existing task
        task?.cancel()
        
        guard let url = url else {
            self.image = nil
            return
        }
        
        self.url = url
        
        // Check cache first
        if let cached = Self.cache.object(forKey: url as NSURL) {
            self.image = cached
            return
        }
        
        isLoading = true
        error = nil
        
        task = Task {
            do {
                let loadedImage = try await fetchImage(from: url)
                
                guard !Task.isCancelled else { return }
                
                // Cache the image
                Self.cache.setObject(loadedImage, forKey: url as NSURL)
                
                self.image = loadedImage
                self.isLoading = false
            } catch {
                guard !Task.isCancelled else { return }
                
                self.error = error
                self.isLoading = false
                
                #if DEBUG
                print("🖼️ Image load failed for \(url): \(error.localizedDescription)")
                #endif
            }
        }
    }
    
    private func fetchImage(from url: URL) async throws -> UIImage {
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = true
        
        // Add common headers that help with cookie handling
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://groups.parkslopeparents.com", forHTTPHeaderField: "Referer")
        
        #if DEBUG
        // Log cookies being sent
        if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            print("🍪 Sending \(cookies.count) cookies for \(url.host ?? "unknown")")
            for cookie in cookies {
                print("   - \(cookie.name): \(cookie.value.prefix(20))...")
            }
        }
        #endif
        
        let (data, response) = try await Self.session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ImageLoadError.invalidResponse
        }
        
        #if DEBUG
        print("🖼️ Image response: \(httpResponse.statusCode) for \(url.lastPathComponent)")
        #endif
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ImageLoadError.httpError(httpResponse.statusCode)
        }
        
        guard let image = UIImage(data: data) else {
            throw ImageLoadError.invalidImageData
        }
        
        return image
    }
    
    func cancel() {
        task?.cancel()
        task = nil
    }
    
    // MARK: - Cache Management
    
    static func clearCache() {
        cache.removeAllObjects()
    }
    
    static func preloadImage(from url: URL) {
        Task {
            // Check if already cached
            if cache.object(forKey: url as NSURL) != nil {
                return
            }
            
            var request = URLRequest(url: url)
            request.httpShouldHandleCookies = true
            
            do {
                let (data, _) = try await session.data(for: request)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        cache.setObject(image, forKey: url as NSURL)
                    }
                }
            } catch {
                // Silently fail preload
            }
        }
    }
}

// MARK: - Error Types

enum ImageLoadError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int)
    case invalidImageData
    case authenticationRequired
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            if code == 401 || code == 403 {
                return "Authentication required"
            }
            return "Server error (\(code))"
        case .invalidImageData:
            return "Invalid image data"
        case .authenticationRequired:
            return "Please log in to view images"
        }
    }
}
