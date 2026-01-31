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
        
        // Allow inline media playback and JavaScript
        config.allowsInlineMediaPlayback = true
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator  // Handle JS alerts, new windows, etc.
        
        // Enable link interactions
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        
        webView.load(URLRequest(url: loginURL))
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: LoginWebView
        
        init(parent: LoginWebView) {
            self.parent = parent
        }
        
        // MARK: - WKNavigationDelegate
        
        // Allow all navigation actions (clicking links)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
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
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            #if DEBUG
            print("⚠️ WebView navigation failed: \(error.localizedDescription)")
            #endif
        }
        
        // MARK: - WKUIDelegate
        
        // Handle links that open in new windows (target="_blank")
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Load the URL in the same webview instead of opening a new window
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
        
        // Handle JavaScript alerts
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }
        
        // Handle JavaScript confirm dialogs
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(true)
        }
        
        // Handle JavaScript text input prompts
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            completionHandler(defaultText)
        }
        
        private func checkForSuccessfulLogin(webView: WKWebView) {
            // Check for session cookie and sync to HTTPCookieStorage
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                let relevantCookies = cookies.filter { cookie in
                    cookie.domain.contains("parkslopeparents.com") ||
                    cookie.domain.contains("groups.io")
                }
                
                // Sync ALL relevant cookies to HTTPCookieStorage for image loading
                for cookie in relevantCookies {
                    HTTPCookieStorage.shared.setCookie(cookie)
                    #if DEBUG
                    print("🍪 Synced cookie: \(cookie.name) for \(cookie.domain)")
                    #endif
                }
                
                // Check for the actual session cookie (named "groupsio" on .groups.parkslopeparents.com)
                let hasSession = relevantCookies.contains { cookie in
                    cookie.name == "groupsio" || 
                    cookie.name == "_groupsio_session" || 
                    cookie.name.contains("session")
                }
                
                #if DEBUG
                print("🔐 Login check - hasSession: \(hasSession), cookies: \(relevantCookies.map { $0.name })")
                #endif
                
                if hasSession {
                    Task { @MainActor in
                        self?.parent.onLoginDetected()
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
