# PSP Classifieds — iOS App

Native SwiftUI app for browsing Park Slope Parents classifieds.

## Requirements

- iOS 17+
- Xcode 15+

## Features

- **Main Feed** — scrollable list of classified posts with infinite scroll and pull-to-refresh
- **Category Tabs** — quick filters for All, For Sale, For Free, and ISO posts
- **Hashtag Filtering** — tap any hashtag pill to filter, or use the filter sheet to combine multiple hashtags and date ranges
- **Full-Text Search** — search across post titles and bodies
- **Post Detail** — full message view with image gallery, sender info, email action, and save/bookmark
- **Sharing** — send a post to an iMessage thread (or any share destination) from the detail view's toolbar, its Share button, or a long press on a feed card
- **Deep Links** — shared links open straight to the post in the app via universal links
- **Saved Posts** — bookmark posts locally with SwiftData persistence
- **Background Refresh** — uses `BGAppRefreshTask` to keep the feed up to date
- **Authenticated Images** — loads photos from groups.io via shared WKWebView cookies

## Architecture

MVVM with `@Observable` (iOS 17+). The app is read-only — all data comes from the [backend API](../server/README.md).

### Key Layers

| Layer | Files | Role |
|-------|-------|------|
| **Views** | `MainFeedView`, `PostCardView`, `PostDetailView`, `PostPagerView`, `SearchView`, `SavedPostsView`, `FilterSheet`, `MainTabView` | SwiftUI screens and components |
| **ViewModels** | `FeedViewModel`, `FilterViewModel`, `SearchViewModel` | State management and API orchestration |
| **Models** | `Post`, `Hashtag`, `Category`, `Attachment`, `SavedPost` | Data types matching the API response |
| **Services** | `APIClient`, `AuthenticatedImageLoader`, `BackgroundFetchManager`, `FeedCache`, `SavedPostsManager` | Networking, image auth, caching, persistence |
| **Auth** | `AuthManager`, `LoginView` | WKWebView login flow for groups.io cookie-based image auth |

### Authentication Flow

The API itself requires no auth. However, post images are hosted on `groups.parkslopeparents.com` and require a valid session cookie.

1. On launch, `AuthManager` checks for a valid session cookie
2. If missing/expired, the app presents a `WKWebView` login screen
3. User logs into groups.io — cookies sync to `HTTPCookieStorage.shared`
4. `AuthenticatedImageLoader` uses those cookies for all image requests

### Shared Post Links

Sharing a post produces a `https://psp-api.fly.dev/p/{post_id}` link. The backend
serves an [app-site-association file](../server/README.md#shared-post-links) for
`/p/*`, which makes these universal links: iOS opens the app when the recipient
has it installed, and falls back to a web page linking to groups.io when they
don't.

1. `PostLink` builds and parses those URLs (`Extensions/Post+Sharing.swift`)
2. `ContentView.onOpenURL` pulls the post id out of an incoming link, fetches the post, and hands it to the feed to navigate to
3. Links that arrive before login are held until the user is through the login screen

This requires `applinks:psp-api.fly.dev` in `PSPClassifieds.entitlements` and the
Associated Domains capability on the App ID.

## Project Structure

```
PSPClassifieds/
├── PSPClassifiedsApp.swift          # App entry point, SwiftData container setup
├── Auth/
│   ├── AuthManager.swift            # Cookie-based auth state
│   └── LoginView.swift              # WKWebView login
├── Models/
│   ├── Post.swift
│   ├── Hashtag.swift
│   ├── Category.swift
│   ├── Attachment.swift
│   └── SavedPost.swift              # SwiftData @Model
├── Views/
│   ├── MainTabView.swift            # Tab bar (Feed / Saved)
│   ├── MainFeedView.swift           # Feed + filters + infinite scroll
│   ├── PostCardView.swift           # Card in the feed list
│   ├── PostDetailView.swift         # Full post detail
│   ├── PostPagerView.swift          # Swipeable post navigation
│   ├── SearchView.swift             # Full-text search
│   ├── SavedPostsView.swift         # Bookmarked posts
│   └── FilterSheet.swift            # Hashtag + date filter UI
├── ViewModels/
│   ├── FeedViewModel.swift          # Feed state, pagination, filtering
│   ├── FilterViewModel.swift        # Filter sheet state
│   └── SearchViewModel.swift        # Search state
├── Services/
│   ├── APIClient.swift              # Async/await API client (actor)
│   ├── AuthenticatedImageLoader.swift
│   ├── BackgroundFetchManager.swift # BGAppRefreshTask scheduling
│   ├── FeedCache.swift              # Local feed caching
│   ├── MockData.swift               # Mock data for previews/testing
│   └── SavedPostsManager.swift      # SwiftData CRUD for saved posts
├── Components/
│   ├── AuthenticatedImage.swift     # Cookie-aware image view
│   ├── HashtagPill.swift            # Colored hashtag badge
│   ├── PostShareLink.swift          # Share sheet entry point for a post
│   └── SkeletonLoader.swift         # Loading placeholder
├── Extensions/
│   ├── Post+Sharing.swift           # Share text and link for a post
│   └── String+HTMLDecoding.swift    # HTML entity decoding
└── Resources/
    └── Assets.xcassets
```

## API

The app talks to a single FastAPI backend at `https://psp-api.fly.dev/api/v1`.

| Endpoint | Description |
|----------|-------------|
| `GET /messages` | List posts with optional `hashtags`, `search`, `since`, `limit`, `cursor` params |
| `GET /messages/{id}` | Single post detail |
| `GET /hashtags` | All hashtags with counts and colors |

See the [server README](../server/README.md) for full API and backend details.

## Running

1. Open `PSPClassifieds.xcodeproj` in Xcode
2. Select an iOS 17+ simulator or device
3. Build and run (⌘R)

On first launch, the app will prompt you to log into your Park Slope Parents account (required for loading post images).
