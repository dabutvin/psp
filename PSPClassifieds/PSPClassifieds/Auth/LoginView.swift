import SwiftUI
import WebKit

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var showWebView = false
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Logo/Header
            VStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                
                Text("PSP Classifieds")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Browse Park Slope Parents\nclassifieds on the go")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Info
            VStack(spacing: 12) {
                InfoRow(icon: "lock.shield", text: "Sign in with your PSP account")
                InfoRow(icon: "photo.on.rectangle", text: "View listing photos")
                InfoRow(icon: "envelope", text: "Contact sellers directly")
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Login Button
            Button {
                showWebView = true
            } label: {
                Text("Sign in to PSP")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            
            #if DEBUG
            Button("Skip (Debug)") {
                authManager.onLoginSuccess()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            #endif
            
            Spacer()
                .frame(height: 32)
        }
        .sheet(isPresented: $showWebView) {
            LoginWebViewContainer(isPresented: $showWebView)
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

// MARK: - WebView Container
struct LoginWebViewContainer: View {
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool
    @State private var isLoading = true
    @State private var currentURL: URL?
    
    var body: some View {
        NavigationStack {
            ZStack {
                LoginWebView(
                    isLoading: $isLoading,
                    currentURL: $currentURL,
                    onLoginDetected: {
                        authManager.onLoginSuccess()
                        isPresented = false
                    }
                )
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
            .navigationTitle("Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// MARK: - WebView
struct LoginWebView: UIViewRepresentable {
    @Binding var isLoading: Bool
    @Binding var currentURL: URL?
    let onLoginDetected: () -> Void
    
    private let loginURL = URL(string: "https://groups.parkslopeparents.com")!
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Shares cookies with HTTPCookieStorage
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: loginURL))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: LoginWebView
        
        init(parent: LoginWebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.currentURL = webView.url
            
            // Check if user successfully logged in
            // Groups.io typically redirects to the groups page after login
            checkForSuccessfulLogin(webView: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
        
        private func checkForSuccessfulLogin(webView: WKWebView) {
            // Check for session cookie
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let hasSession = cookies.contains { cookie in
                    cookie.domain.contains("parkslopeparents.com") &&
                    (cookie.name == "_groupsio_session" || cookie.name.contains("session"))
                }
                
                if hasSession {
                    // Also check if we're on a logged-in page (not login page)
                    webView.evaluateJavaScript("document.querySelector('.logged-in, .user-menu, [data-user]') !== null") { result, _ in
                        if let isLoggedIn = result as? Bool, isLoggedIn {
                            Task { @MainActor in
                                self?.parent.onLoginDetected()
                            }
                        }
                    }
                }
            }
            
            // Alternative: check URL patterns that indicate successful login
            if let url = webView.url?.absoluteString {
                // If we're on the main groups page (not login), consider it successful
                if url.contains("/g/") && !url.contains("/login") && !url.contains("/join") {
                    Task { @MainActor in
                        self.parent.onLoginDetected()
                    }
                }
            }
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager())
}
