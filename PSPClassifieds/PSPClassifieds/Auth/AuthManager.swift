import Foundation
import WebKit

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isCheckingAuth = true
    
    private let groupsURL = URL(string: "https://groups.parkslopeparents.com")!
    
    // The actual cookie name used by groups.parkslopeparents.com
    private let sessionCookieNames = ["groupsio", "_groupsio_session"]
    
    func checkLoginStatus() {
        isCheckingAuth = true
        
        // Check for valid session cookie
        let cookies = HTTPCookieStorage.shared.cookies(for: groupsURL) ?? []
        let hasSessionCookie = cookies.contains { cookie in
            sessionCookieNames.contains(cookie.name) && !cookie.isExpired
        }
        
        #if DEBUG
        print("🍪 Checking cookies for \(groupsURL):")
        for cookie in cookies {
            print("   - \(cookie.name): domain=\(cookie.domain), expired=\(cookie.isExpired)")
        }
        print("🔐 Has session cookie: \(hasSessionCookie)")
        #endif
        
        isAuthenticated = hasSessionCookie
        isCheckingAuth = false
        
        #if DEBUG
        // For development, allow bypass
        if ProcessInfo.processInfo.environment["SKIP_AUTH"] == "1" {
            isAuthenticated = true
        }
        #endif
    }
    
    func logout() {
        // Clear cookies for groups.io domain
        let cookies = HTTPCookieStorage.shared.cookies(for: groupsURL) ?? []
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
        }
        
        // Clear cached images (they may contain authenticated content)
        AuthenticatedImageLoader.clearCache()
        
        // Also clear WKWebView data
        WKWebsiteDataStore.default().removeData(
            ofTypes: [WKWebsiteDataTypeCookies],
            modifiedSince: Date.distantPast
        ) { [weak self] in
            Task { @MainActor in
                self?.isAuthenticated = false
            }
        }
    }
    
    func onLoginSuccess() {
        isAuthenticated = true
    }
}

// MARK: - Cookie Extension
private extension HTTPCookie {
    var isExpired: Bool {
        guard let expiresDate = expiresDate else {
            // Session cookie - valid until app closes
            return false
        }
        return expiresDate < Date()
    }
}
