import SwiftUI

/// An image view that loads images with authentication cookies
/// Required for loading images from groups.parkslopeparents.com
struct AuthenticatedImage<Placeholder: View, ErrorView: View>: View {
    let url: URL?
    let contentMode: ContentMode
    @ViewBuilder let placeholder: () -> Placeholder
    @ViewBuilder let errorView: (Error) -> ErrorView
    
    @StateObject private var loader = AuthenticatedImageLoader()
    
    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder errorView: @escaping (Error) -> ErrorView
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
        self.errorView = errorView
    }
    
    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loader.isLoading {
                placeholder()
            } else if let error = loader.error {
                errorView(error)
            } else {
                placeholder()
            }
        }
        .onAppear {
            loader.load(from: url)
        }
        .onChange(of: url) { oldValue, newValue in
            if oldValue != newValue {
                loader.load(from: newValue)
            }
        }
        .onDisappear {
            loader.cancel()
        }
    }
}

// MARK: - Convenience Initializers

extension AuthenticatedImage where Placeholder == ProgressView<EmptyView, EmptyView>, ErrorView == DefaultImageErrorView {
    /// Simple initializer with default placeholder and error views
    init(url: URL?, contentMode: ContentMode = .fill) {
        self.init(
            url: url,
            contentMode: contentMode,
            placeholder: { ProgressView() },
            errorView: { error in DefaultImageErrorView(error: error) }
        )
    }
}

extension AuthenticatedImage where ErrorView == DefaultImageErrorView {
    /// Initializer with custom placeholder
    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            contentMode: contentMode,
            placeholder: placeholder,
            errorView: { error in DefaultImageErrorView(error: error) }
        )
    }
}

// MARK: - Default Error View

struct DefaultImageErrorView: View {
    let error: Error
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: errorIcon)
                .font(.title2)
                .foregroundStyle(.tertiary)
            
            if showErrorText {
                Text(errorText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.tertiarySystemBackground))
    }
    
    private var errorIcon: String {
        if let imageError = error as? ImageLoadError {
            switch imageError {
            case .authenticationRequired, .httpError(401), .httpError(403):
                return "lock.fill"
            default:
                return "photo"
            }
        }
        return "photo"
    }
    
    private var showErrorText: Bool {
        if let imageError = error as? ImageLoadError {
            switch imageError {
            case .authenticationRequired, .httpError(401), .httpError(403):
                return true
            default:
                return false
            }
        }
        return false
    }
    
    private var errorText: String {
        "Login required"
    }
}

// MARK: - Thumbnail Variant

/// Optimized authenticated image for thumbnails with caching
struct AuthenticatedThumbnail: View {
    let url: URL?
    let size: CGFloat
    
    init(url: URL?, size: CGFloat = 80) {
        self.url = url
        self.size = size
    }
    
    var body: some View {
        AuthenticatedImage(
            url: url,
            contentMode: .fill
        ) {
            Rectangle()
                .fill(Color(.tertiarySystemBackground))
                .overlay {
                    ProgressView()
                        .scaleEffect(0.8)
                }
        } errorView: { _ in
            Rectangle()
                .fill(Color(.tertiarySystemBackground))
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Authenticated Image") {
    VStack(spacing: 20) {
        // With real URL (will fail without auth)
        AuthenticatedImage(
            url: URL(string: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725407/1/IMG_0740.jpeg")
        )
        .frame(width: 200, height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        
        // Thumbnail variant
        AuthenticatedThumbnail(
            url: URL(string: "https://placekitten.com/200/200"),
            size: 80
        )
    }
    .padding()
}
