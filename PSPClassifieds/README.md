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
│   └── SkeletonLoader.swift         # Loading placeholder
├── Extensions/
│   └── String+HTMLDecoding.swift    # HTML entity decoding
└── Resources/
    └── Assets.xcassets
```

Beside the project, rather than inside the app's sources:

```
PSPClassifieds/
├── ExportOptions.plist              # How testflight.yml exports the archive
└── Tools/
    ├── bootstrap_signing.py         # Creates/lists/revokes the signing certificate over the API
    └── prepare_signing_secrets.sh   # Checks and encodes a certificate exported from a Mac
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

## How changes ship

```
PR to main ──► ci.yml ──► build and run the unit tests on a simulator
     ▼
merge to main ──► testflight.yml ──► TestFlight (build number = UTC timestamp)
```

| Workflow | Trigger | Action |
|---|---|---|
| `ci.yml` | PR touching `PSPClassifieds/**` | Build for simulator, no signing, then run the unit tests |
| `testflight.yml` | Push to main touching `PSPClassifieds/**` | Archive, sign, upload to TestFlight. Also runnable by hand from the Actions tab, on any branch |
| `signing-setup.yml` | Manual | Create, list or revoke the signing certificate and profile over the App Store Connect API |

Notes on the details:

- **Signing.** Runners are wiped after every job, so `testflight.yml` imports a distribution certificate and App Store profile into a throwaway keychain (`.github/actions/setup-signing`) and archives with `CODE_SIGN_STYLE=Manual`. It deliberately does *not* pass `-allowProvisioningUpdates`: with an empty keychain that flag makes Xcode ask Apple for a **brand new certificate on every run** and abandon it, so after a handful of builds the account hits its certificate limit and every archive fails with "Your account has reached the maximum number of certificates." Where the certificate comes from is covered under [Signing](#signing) below.
- **Versioning.** `MARKETING_VERSION` lives in the Xcode project; the build number is a `YYYYMMDDHHMM` timestamp injected at archive time, so it always increases and never has to be bumped by hand.
- **Xcode.** TestFlight builds use the newest Xcode 26 on a `macos-26` runner, because App Store Connect only accepts builds made with a current SDK. `ci.yml` still pins the older Xcode it was written against.
- **Encryption compliance.** `Info.plist` sets `ITSAppUsesNonExemptEncryption` to false — the app only talks HTTPS, which is exempt — so a build is ready for testers as soon as App Store Connect finishes processing it, instead of waiting in "Missing Compliance" for someone to answer the export question by hand.
- **Concurrency.** Everything that touches the account's certificates shares one `apple-signing` group and never cancels, so two merges in quick succession both ship, one after the other, and no two runs mint or revoke at the same time.
- **Doc-only changes.** A push that only touches `*.md` under `PSPClassifieds/`, or anything under `server/`, does not ship a build.

## Required Secrets

Set these in GitHub repo settings → Secrets and variables → Actions.

| Secret | Purpose | How to get it |
|---|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | API key ID, for uploading builds | App Store Connect → Users and Access → Integrations → Keys |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID | Same page as above |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | API key (`.p8` file contents), **raw text** | Paste the full text including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` |
| `TEAM_ID` | Optional. Apple Developer Team ID | developer.apple.com → Membership. Defaults to the team in `project.pbxproj` |
| `APPLE_DISTRIBUTION_CERT_P12` | Optional. Distribution certificate **and its private key**, base64 | [One stored certificate](#one-stored-certificate) |
| `APPLE_DISTRIBUTION_CERT_PASSWORD` | Optional. Password protecting that `.p12` | Same |
| `APPLE_PROVISIONING_PROFILE` | Optional. App Store profile for `com.psp.classifieds`, base64 | Same |

The API key needs the **App Manager** role (or Admin): it uploads builds, and by default also creates and revokes certificates. The App Store Connect app record must exist with bundle ID `com.psp.classifieds` before the first TestFlight upload.

## Signing

A distribution certificate is only usable together with the private key it was created from, and Apple caps each account at a couple of certificates — so a build cannot just ask for a fresh one each time. Apple's instructions have you make the key in Keychain Access on a Mac, but nothing requires that: the key can be generated anywhere, the signing request submitted over the App Store Connect API, and the `.p12` assembled with openssl. `Tools/bootstrap_signing.py` does that, so none of what follows needs a Mac.

### Per-build certificates

This is what happens by default, with no setup beyond the App Store Connect API key. Each TestFlight build creates its own certificate and profile, signs, uploads, and a later build retires them, so the account holds one certificate at rest and never approaches the limit. On the way it switches on, for the App ID, whatever capabilities the app's entitlements claim — push notifications, for the new-post alerts — so a profile is never minted short of what the archive asks for.

The sweep runs at the *start* of a build rather than the end of the previous one. That keeps revocation well away from App Store Connect still processing an upload, and it collects anything a cancelled run left behind, so the account cannot silently fill up again. Profiles are named `PSP Classifieds CI <run id>`, which is how the sweep tells its own certificates from a person's: a certificate survives as long as some profile references it, and if you have one with no profile at all, add `--keep-serial <serial>` to the cleanup step.

Revoking a distribution certificate does not disturb builds already on TestFlight, because Apple re-signs those for distribution. It does break a build still in App Review, so if this app is ever submitted to the App Store, give that submission a certificate the TestFlight sweep will not touch.

What you give up is independence from Apple's API: every build calls it twice, and two builds must never mint at once — hence the shared `apple-signing` concurrency group across `testflight.yml` and `signing-setup.yml`.

### One stored certificate

If you would rather builds never touch Apple's certificate API, set the three `APPLE_*` secrets and every build reuses that one certificate instead of minting anything. From a phone:

1. Create a [fine-grained personal access token](https://github.com/settings/personal-access-tokens/new) scoped to this repository with **Secrets: read and write**, and save it as a secret named `SIGNING_BOOTSTRAP_PAT`. The built-in workflow token cannot write secrets, which is the only reason a PAT is needed.
2. Actions → **Signing Setup** → *Run workflow* → task `create`. It registers the App ID if missing, creates the certificate and profile, and sets the three secrets.
3. Delete `SIGNING_BOOTSTRAP_PAT`. The next build signs with the stored certificate.

Renew it before it expires a year later. Note that a GitHub secret can be written but never read back, so a certificate created this way lives only inside Actions; that is recoverable by revoking and re-running `create`, but if you also want the `.p12` in hand, run the script locally instead:

```bash
export APP_STORE_CONNECT_API_KEY_ID=... APP_STORE_CONNECT_ISSUER_ID=...
export APP_STORE_CONNECT_API_KEY_CONTENT="$(cat ~/Downloads/AuthKey_XXXXXX.p8)"

PSPClassifieds/Tools/bootstrap_signing.py list
PSPClassifieds/Tools/bootstrap_signing.py create   # writes the three values to .signing-secrets/
```

### Clearing out certificates

Actions → **Signing Setup** → task `list` shows every certificate and profile on the account with their ids, and task `revoke` takes those ids. That is the way out of "your account has reached the maximum number of certificates": revoke the ones nobody holds a private key for. Certificates whose key is lost — anything an old CI run created and threw away — are only taking up slots.

### Using a certificate from a Mac

If you would rather use Xcode's own certificate flow for the stored-certificate route:

1. Xcode → Settings → Accounts → select the team → *Manage Certificates* → `+` → *Apple Distribution*.
2. Keychain Access → *My Certificates* → right-click the `Apple Distribution: …` row → *Export*, save as `.p12`, set a password. Expanding the row must reveal a private key; if it does not, this Mac does not have the key and the export is useless.
3. developer.apple.com → Profiles → `+` → *App Store Connect* → App ID `com.psp.classifieds` → pick that certificate → download the `.mobileprovision`.
4. Check and encode the pair, which also confirms the profile was really issued for that certificate:

```bash
PSPClassifieds/Tools/prepare_signing_secrets.sh ~/Downloads/Certificates.p12 ~/Downloads/PSPClassifieds_AppStore.mobileprovision
```

5. Set the three secrets with the `gh secret set` commands it prints, then delete `.signing-secrets/` and keep the `.p12` and its password somewhere safe.

Local development needs none of this: the project keeps `CODE_SIGN_STYLE = Automatic`, so Xcode signs with your personal team, and only the TestFlight workflow overrides it with the shared identity.
