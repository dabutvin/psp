# PSP Classifieds - iPhone App Plan

## Overview
A native iOS app for browsing Park Slope Parents classifieds (For Sale, For Free, ISO posts). Clean, fast, focused on the marketplace use case.

---

## Core Features (from Wireframe)

### Navigation
- **Header**: "PSP Classifieds" title + filter icon + search icon
- **Tab Bar**: "All" | "For sale" | "For free" | "ISO" (In Search Of)
- Tabs filter by hashtag (#ForSale, #ForFree, #ISO) or show all

### List View (Cards)
Each card shows:
- **Thumbnail** (if attachments exist) - static preview, tap card for detail
- **Title** (subject line)
- **Price** (from server, if present)
- **Hashtags** as pills (#ForSale, #NorthSlope, etc.)
- **Timestamp** (relative: "4PM", "2h ago", "Yesterday")

### Detail View
Tap card → navigate to full-screen detail page.

Detail page shows:
- Full image gallery (swipeable)
- **From**: sender name
- **Date**: full timestamp
- **Body**: full message text (HTML rendered cleanly)
- **Actions**:
  - 📧 "Send email" - opens Mail.app compose
  - 🔖 "Save" - bookmark for later

---

## Screens

### 1. Main Feed
```
┌─────────────────────────────────┐
│  PSP Classifieds    [≡] [🔍]   │
├─────────────────────────────────┤
│ [All] [For sale] [For free] [ISO] │
├─────────────────────────────────┤
│  ┌─────────────────────────────┐│
│  │ 🖼  Title                   ││
│  │     $40                     ││
│  │     #ForSale #NorthSlope    ││
│  └─────────────────────────────┘│
│  ┌─────────────────────────────┐│
│  │ 🖼  Title                   ││
│  │     ...                     ││
│  └─────────────────────────────┘│
│           (scrollable)          │
└─────────────────────────────────┘
```

### 2. Detail View
```
┌─────────────────────────────────┐
│  ←  Post Details               │
├─────────────────────────────────┤
│  ┌─────────────────────────────┐│
│  │                             ││
│  │      [Image Gallery]        ││
│  │        ● ○ ○ ○              ││
│  └─────────────────────────────┘│
│                                 │
│  FS: Size 6 Adidas bundle      │
│  $40                           │
│  #ForSale  #NorthSlope         │
│                                 │
│  From: Claire Bourgeois        │
│  Date: Fri, 30 Jan 2026        │
│                                 │
│  Hi PSP,                       │
│  Selling bundle of 5 pairs...  │
│  Pick up in North Slope.       │
│                                 │
│  ┌──────────┐  ┌──────────┐    │
│  │ ✉ Email  │  │ 🔖 Save  │    │
│  └──────────┘  └──────────┘    │
└─────────────────────────────────┘
```

### 3. Search
- Full-text search across titles and bodies
- Recent searches
- Filter by any hashtag

### 4. Saved Posts
- List of bookmarked items
- Persisted locally (SwiftData)

### 5. Filters/Settings
- Hashtag filter (any tag: #NorthSlope, #BabyGear, #Toddler, etc.)
- Price range filter
- Date range

---

## Data Model (Client-side)

```swift
struct Post: Identifiable, Codable {
    let id: Int
    let topicId: Int
    let created: Date
    let subject: String
    let body: String
    let snippet: String
    let senderName: String
    let hashtags: [Hashtag]
    let attachments: [Attachment]?
    
    // Derived
    var price: String? // from server
    var category: Category // .forSale, .forFree, .iso
}

struct Hashtag: Codable {
    let name: String
    let colorHex: String
}

struct Attachment: Codable {
    let url: String
    let thumbnailUrl: String?
}

enum Category: String {
    case all = ""             // no filter
    case forSale = "ForSale"
    case forFree = "ForFree"  
    case iso = "ISO"
}
```

---

## Technical Stack

### Framework
- **SwiftUI** - modern, declarative UI
- **iOS 17+** minimum (allows SwiftData, modern APIs)

### Networking
- URLSession with async/await
- Simple API client talking to our FastAPI backend

### Persistence
- **SwiftData** for saved posts and cache
- UserDefaults for simple preferences

### Architecture
- MVVM with @Observable (iOS 17+)
- Keep it simple - this is a read-only app

---

## API Integration

Endpoints needed (from SERVERPLAN.md):

```swift
// Fetch posts by category
GET /api/v1/messages?hashtag=ForSale&limit=20&cursor=xxx

// Single post detail
GET /api/v1/messages/{id}

// Search
GET /api/v1/messages?search=adidas&hashtag=ForSale

// Hashtags list (for filters)
GET /api/v1/hashtags
```

### Image Authentication (WebView Cookie Sharing)
Attachment URLs at `groups.parkslopeparents.com` require authentication. 

**Approach**: User logs in via WebView, cookies shared with image requests.

**Login Flow**:
1. On first launch (or when session expires), present WebView
2. Load `https://groups.parkslopeparents.com` login page
3. User logs in with their PSP credentials
4. Detect successful login (URL change or page content)
5. Cookies automatically stored in shared `HTTPCookieStorage`
6. Dismiss WebView, proceed to app

**Implementation**:
```swift
import WebKit

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    
    // Use WKWebView with default WKWebsiteDataStore
    // Cookies auto-sync to HTTPCookieStorage.shared
    
    func checkLoginStatus() {
        // Check for valid session cookie
        let cookies = HTTPCookieStorage.shared.cookies(for: 
            URL(string: "https://groups.parkslopeparents.com")!)
        isAuthenticated = cookies?.contains { $0.name == "session" } ?? false
    }
}

// WebView for login
struct LoginWebView: UIViewRepresentable {
    let url = URL(string: "https://groups.parkslopeparents.com")!
    @Binding var isAuthenticated: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // Shares cookies
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }
    
    // Coordinator detects successful login
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check if logged in (look for dashboard URL or specific element)
        }
    }
}
```

**Image Loading** (AsyncImage or custom loader):
```swift
// Cookies automatically included when loading from same domain
AsyncImage(url: URL(string: attachment.thumbnailUrl)) { image in
    image.resizable().aspectRatio(contentMode: .fill)
} placeholder: {
    ProgressView()
}
```

**Session Management**:
- Store login state in UserDefaults
- Check cookie validity on app launch
- Handle session expiry gracefully (re-show login WebView)
- Consider: "Stay logged in" / "Remember me" if groups.io supports it

**Edge Cases**:
- Cookie expiry → detect 401/redirect, prompt re-login
- No network → show cached images or placeholder
- User logs out on web → session invalidated, handle gracefully

### Offline Support
- Cache recent posts locally
- Show cached data immediately, refresh in background
- "Pull to refresh" pattern

---

## UX Considerations

### Performance
- Lazy load images
- Prefetch next page while scrolling
- Skeleton loaders while fetching

### Interactions
- Pull to refresh
- Infinite scroll pagination
- Haptic feedback on actions
- Swipe actions on cards? (save, share)

### Infinite Scroll Implementation
```swift
class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
    @Published var hasMore = true
    
    private var nextCursor: String? = nil
    
    func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        
        let response = await api.getMessages(
            hashtag: currentHashtag,
            limit: 20,
            cursor: nextCursor
        )
        
        posts.append(contentsOf: response.messages)
        nextCursor = response.nextCursor
        hasMore = response.hasMore
        isLoading = false
    }
    
    func refresh() async {
        nextCursor = nil
        hasMore = true
        posts = []
        await loadMore()
    }
}

// In SwiftUI List/LazyVStack
ForEach(viewModel.posts) { post in
    PostCardView(post: post)
        .onAppear {
            // Trigger load when near end (last 3 items)
            if post == viewModel.posts.suffix(3).first {
                Task { await viewModel.loadMore() }
            }
        }
}
```

**Key behaviors:**
- Load 20 posts per page
- Trigger next page when user scrolls to last 3 items
- Show loading spinner at bottom while fetching
- Pull-to-refresh resets to page 1
- Cursor-based (stable during inserts of new posts)

### Accessibility
- VoiceOver labels
- Dynamic Type support
- Sufficient color contrast

---

## Phase Breakdown

### Phase 1: Core Reading Experience
- [ ] Project setup (Xcode, SwiftUI)
- [ ] API client + mock data
- [ ] WebView login flow (groups.parkslopeparents.com)
- [ ] Cookie-authenticated image loading
- [ ] Main feed with tabs
- [ ] Card component
- [ ] Detail view
- [ ] Basic pull-to-refresh

### Phase 2: Search & Filters
- [ ] Search UI
- [ ] Search API integration
- [ ] Filter sheet (hashtags, date)
- [ ] Recent searches

### Phase 3: Save & Personalize
- [ ] Save/bookmark posts
- [ ] Saved posts tab
- [ ] Local persistence (SwiftData)

### Phase 4: Polish
- [ ] Image gallery viewer
- [ ] Share sheet
- [ ] Push notifications? (new posts matching criteria)
- [ ] Widget? (latest deals)

---

## Open Questions

1. **Push notifications**
   - Would require server-side work (APNs)
   - Maybe Phase 2 feature - alert on new posts with keywords?

2. **Authentication**
   - App is read-only for our API, no auth needed there
   - groups.io login required for loading images (WebView cookie sharing)

---

## Design Notes

### Typography
- System fonts (SF Pro) for iOS native feel
- Clear hierarchy: title (semibold), price (bold), body (regular)

### Colors
- Use hashtag colors from API for pills
- Clean white/gray card backgrounds
- Accent color TBD (PSP brand color?)

### Imagery
- Rounded corners on thumbnails
- Placeholder for posts without images
- Respect aspect ratios in gallery

---

## File Structure (Proposed)

```
PSPClassifieds/
├── PSPClassifiedsApp.swift
├── Models/
│   ├── Post.swift
│   ├── Hashtag.swift
│   └── Category.swift
├── Views/
│   ├── MainFeedView.swift
│   ├── PostCardView.swift
│   ├── PostDetailView.swift
│   ├── SearchView.swift
│   ├── SavedPostsView.swift
│   └── FilterSheet.swift
├── ViewModels/
│   ├── FeedViewModel.swift
│   ├── SearchViewModel.swift
│   └── SavedPostsViewModel.swift
├── Services/
│   ├── APIClient.swift
│   └── PersistenceManager.swift
├── Components/
│   ├── HashtagPill.swift
│   ├── ImageGallery.swift
│   └── SkeletonLoader.swift
└── Resources/
    └── Assets.xcassets
```
