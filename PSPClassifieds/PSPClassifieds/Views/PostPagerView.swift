import SwiftUI

/// A pageable container that allows swiping between post details (with infinite scroll)
struct PostPagerView: View {
    let viewModel: FeedViewModel
    let initialPost: Post
    
    @State private var selectedPostId: Int
    @Environment(SavedPostsManager.self) private var savedPostsManager
    
    init(viewModel: FeedViewModel, initialPost: Post) {
        self.viewModel = viewModel
        self.initialPost = initialPost
        self._selectedPostId = State(initialValue: initialPost.id)
    }
    
    private var posts: [Post] {
        viewModel.posts
    }
    
    private var currentPost: Post {
        posts.first { $0.id == selectedPostId } ?? initialPost
    }
    
    private var currentIndex: Int {
        posts.firstIndex { $0.id == selectedPostId } ?? 0
    }
    
    private var shouldLoadMore: Bool {
        currentIndex >= posts.count - 3
    }
    
    var body: some View {
        TabView(selection: $selectedPostId) {
            ForEach(posts) { post in
                PostDetailContent(post: post)
                    .tag(post.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle("\(currentIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPostId) {
            if shouldLoadMore {
                Task {
                    await viewModel.loadMore()
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        savedPostsManager.toggleSaved(currentPost)
                    }
                } label: {
                    Image(systemName: savedPostsManager.isSaved(currentPost) ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: savedPostsManager.isSaved(currentPost))
            }
        }
    }
}

/// A static pageable container for posts without infinite scroll (saved posts, search results)
struct StaticPostPagerView: View {
    let posts: [Post]
    let initialPost: Post
    
    @State private var selectedPostId: Int
    @Environment(SavedPostsManager.self) private var savedPostsManager
    
    init(posts: [Post], initialPost: Post) {
        self.posts = posts
        self.initialPost = initialPost
        self._selectedPostId = State(initialValue: initialPost.id)
    }
    
    private var currentPost: Post {
        posts.first { $0.id == selectedPostId } ?? initialPost
    }
    
    private var currentIndex: Int {
        posts.firstIndex { $0.id == selectedPostId } ?? 0
    }
    
    var body: some View {
        TabView(selection: $selectedPostId) {
            ForEach(posts) { post in
                PostDetailContent(post: post)
                    .tag(post.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .navigationTitle("\(currentIndex + 1)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        savedPostsManager.toggleSaved(currentPost)
                    }
                } label: {
                    Image(systemName: savedPostsManager.isSaved(currentPost) ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: savedPostsManager.isSaved(currentPost))
            }
        }
    }
}

/// The actual content of a post detail - extracted for use in pager
struct PostDetailContent: View {
    let post: Post
    @Environment(SavedPostsManager.self) private var savedPostsManager
    
    /// All images: attachments + inline images from body HTML (deduplicated)
    private var allImages: [Attachment] {
        var images: [Attachment] = []
        var seenUrls = Set<String>()
        
        // Add attachments, deduplicating as we go
        for attachment in post.attachments ?? [] {
            if let url = attachment.downloadUrl, !seenUrls.contains(url) {
                seenUrls.insert(url)
                images.append(attachment)
            } else if attachment.downloadUrl == nil {
                // Keep attachments without URLs (shouldn't happen, but be safe)
                images.append(attachment)
            }
        }
        
        // Extract inline images from body HTML
        if let body = post.body {
            let inlineImages = extractInlineImages(from: body)
            for imageUrl in inlineImages {
                // Only add if not already seen
                if !seenUrls.contains(imageUrl) {
                    seenUrls.insert(imageUrl)
                    let attachment = Attachment(
                        downloadUrl: imageUrl,
                        thumbnailUrl: nil,
                        filename: nil,
                        mediaType: "image",
                        attachmentIndex: nil
                    )
                    images.append(attachment)
                }
            }
        }
        
        return images
    }
    
    /// Extract image URLs from HTML img tags
    private func extractInlineImages(from html: String) -> [String] {
        let imgPattern = #"<img\s+[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return []
        }
        
        let nsString = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsString.length))
        
        return matches.compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            let urlRange = match.range(at: 1)
            return nsString.substring(with: urlRange)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image Gallery (includes attachments + inline body images)
                if !allImages.isEmpty {
                    ImageGallery(attachments: allImages)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Title & Price
                    titleAndPrice
                    
                    // Hashtags (show all on detail view)
                    HashtagRow(hashtags: post.hashtags, maxVisible: 100)
                    
                    Divider()
                    
                    // Sender & Date
                    senderInfo
                    
                    Divider()
                    
                    // Body
                    if let body = post.body {
                        HTMLTextView(html: body)
                    } else if let snippet = post.snippet {
                        Text(snippet.decodingHTMLEntities())
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                    
                    // Actions
                    ActionButtons(
                        post: post,
                        isSaved: savedPostsManager.isSaved(post),
                        onToggleSave: {
                            withAnimation(.spring(response: 0.3)) {
                                savedPostsManager.toggleSaved(post)
                            }
                        }
                    )
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 32)
        }
    }
    
    private var titleAndPrice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((post.subject ?? "No Subject").decodingHTMLEntities())
                .font(.title2)
                .fontWeight(.bold)
            
            if let price = post.price {
                Text(price)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.green)
            }
        }
    }
    
    private var senderInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(post.senderName ?? "Unknown Seller", systemImage: "person.circle")
                .font(.subheadline)
            
            if let created = post.created {
                Label(created.formatted(date: .long, time: .shortened), systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Static Pager") {
    NavigationStack {
        StaticPostPagerView(posts: MockData.posts, initialPost: MockData.posts[0])
    }
    .environment(SavedPostsManager())
}
