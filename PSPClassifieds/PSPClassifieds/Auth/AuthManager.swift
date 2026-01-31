import Foundation
import WebKit

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isCheckingAuth = true
    
    private let groupsURL = URL(string: "https://groups.parkslopeparents.com")!
    private let sessionCookieName = "_groupsio_session"
    
    func checkLoginStatus() {
        isCheckingAuth = true
        
        // Check for valid session cookie
        let cookies = HTTPCookieStorage.shared.cookies(for: groupsURL) ?? []
        let hasSessionCookie = cookies.contains { cookie in
            cookie.name == sessionCookieName && !cookie.isExpired
        }
        
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
