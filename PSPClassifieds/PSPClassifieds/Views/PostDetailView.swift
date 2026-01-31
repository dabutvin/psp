import SwiftUI

struct PostDetailView: View {
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
        .navigationTitle("Post Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        savedPostsManager.toggleSaved(post)
                    }
                } label: {
                    Image(systemName: savedPostsManager.isSaved(post) ? "bookmark.fill" : "bookmark")
                }
                .sensoryFeedback(.impact(flexibility: .soft), trigger: savedPostsManager.isSaved(post))
            }
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

// MARK: - Image Gallery
struct ImageGallery: View {
    let attachments: [Attachment]
    @State private var selectedIndex = 0
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                AuthenticatedImage(url: attachment.imageURL, contentMode: .fit) {
                    SkeletonGalleryImage()
                } errorView: { error in
                    VStack(spacing: 8) {
                        Image(systemName: errorIcon(for: error))
                            .font(.largeTitle)
                            .foregroundStyle(.tertiary)
                        Text(errorMessage(for: error))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 300)
        .background(Color(.secondarySystemBackground))
    }
    
    private func errorIcon(for error: Error) -> String {
        if let imageError = error as? ImageLoadError {
            switch imageError {
            case .httpError(401), .httpError(403), .authenticationRequired:
                return "lock.fill"
            default:
                return "photo"
            }
        }
        return "photo"
    }
    
    private func errorMessage(for error: Error) -> String {
        if let imageError = error as? ImageLoadError {
            switch imageError {
            case .httpError(401), .httpError(403), .authenticationRequired:
                return "Login required to view image"
            default:
                return "Failed to load image"
            }
        }
        return "Failed to load image"
    }
}

// MARK: - Skeleton Gallery Image
struct SkeletonGalleryImage: View {
    @State private var isAnimating = false
    
    var body: some View {
        Rectangle()
            .fill(Color(.systemGray5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isAnimating ? 0.6 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - HTML Text View
struct HTMLTextView: View {
    let html: String
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        Text(attributedString)
            .font(.body)
            .environment(\.openURL, OpenURLAction { url in
                openURL(url)
                return .handled
            })
    }
    
    private var attributedString: AttributedString {
        var result = AttributedString()
        
        // Preprocess: normalize line breaks
        var processed = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<li>", with: "• ")
        
        // Parse links and build attributed string
        let linkPattern = #"<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            // Fallback to plain text if regex fails
            let stripped = processed
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .decodingHTMLEntities()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return addPhoneNumberLinks(to: AttributedString(stripped))
        }
        
        let nsString = processed as NSString
        var lastEnd = 0
        
        let matches = regex.matches(in: processed, range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            // Add text before this link
            if match.range.location > lastEnd {
                let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let beforeText = nsString.substring(with: beforeRange)
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .decodingHTMLEntities()
                result.append(AttributedString(beforeText))
            }
            
            // Extract URL and link text
            if match.numberOfRanges >= 3,
               let urlRange = Range(match.range(at: 1), in: processed),
               let textRange = Range(match.range(at: 2), in: processed) {
                let urlString = String(processed[urlRange])
                var linkText = String(processed[textRange])
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .decodingHTMLEntities()
                
                // If link text is empty, use the URL
                if linkText.trimmingCharacters(in: .whitespaces).isEmpty {
                    linkText = urlString
                }
                
                var linkAttrString = AttributedString(linkText)
                if let url = URL(string: urlString) {
                    linkAttrString.link = url
                    linkAttrString.foregroundColor = .accentColor
                }
                result.append(linkAttrString)
            }
            
            lastEnd = match.range.location + match.range.length
        }
        
        // Add remaining text after last link
        if lastEnd < nsString.length {
            let remainingRange = NSRange(location: lastEnd, length: nsString.length - lastEnd)
            let remainingText = nsString.substring(with: remainingRange)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .decodingHTMLEntities()
            result.append(AttributedString(remainingText))
        }
        
        // Trim whitespace from final result
        let finalString = String(result.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If we found no links, just return the cleaned string
        if matches.isEmpty {
            return addPhoneNumberLinks(to: AttributedString(finalString))
        }
        
        // Add phone number links to the result
        return addPhoneNumberLinks(to: result)
    }
    
    /// Detects phone numbers in an AttributedString and makes them clickable SMS links
    private func addPhoneNumberLinks(to attributedString: AttributedString) -> AttributedString {
        var result = attributedString
        
        // Use NSDataDetector to find phone numbers (more reliable than regex)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue) else {
            return result
        }
        
        let fullText = String(result.characters)
        let nsString = fullText as NSString
        let matches = detector.matches(in: fullText, range: NSRange(location: 0, length: nsString.length))
        
        // Process matches in reverse order to preserve indices
        for match in matches.reversed() {
            guard match.resultType == .phoneNumber,
                  let phoneNumber = match.phoneNumber else {
                continue
            }
            
            // Normalize phone number for SMS URL (remove non-digit characters except +)
            let normalized = phoneNumber.replacingOccurrences(of: "[^+0-9]", with: "", options: .regularExpression)
            let smsURL = "sms:\(normalized)"
            
            guard let url = URL(string: smsURL) else {
                continue
            }
            
            // Convert NSRange to String range, then to AttributedString range
            let nsRange = match.range
            guard nsRange.location != NSNotFound,
                  let stringRange = Range(nsRange, in: fullText) else {
                continue
            }
            
            // Use AttributedString's initializer that accepts String ranges
            // We need to find the AttributedString indices that correspond to the String indices
            let startOffset = fullText.distance(from: fullText.startIndex, to: stringRange.lowerBound)
            let endOffset = fullText.distance(from: fullText.startIndex, to: stringRange.upperBound)
            
            // Find indices in AttributedString by iterating through characters
            var currentOffset = 0
            var startAttrIndex: AttributedString.Index?
            var endAttrIndex: AttributedString.Index?
            
            for index in result.characters.indices {
                if currentOffset == startOffset {
                    startAttrIndex = index
                }
                if currentOffset == endOffset {
                    endAttrIndex = index
                    break
                }
                currentOffset += 1
            }
            
            // Handle case where end is at the end of the string
            if endAttrIndex == nil && endOffset == fullText.count {
                endAttrIndex = result.characters.endIndex
            }
            
            // Apply link attribute if we found valid indices
            if let start = startAttrIndex, let end = endAttrIndex {
                let attrRange = start..<end
                result[attrRange].link = url
                result[attrRange].foregroundColor = .accentColor
            }
        }
        
        return result
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let post: Post
    let isSaved: Bool
    let onToggleSave: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Reply Button - opens message on groups.io
            Button {
                openMessage()
            } label: {
                Label("Reply", systemImage: "arrowshape.turn.up.left")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(post.webURL != nil ? Color.accentColor : Color.gray)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(post.webURL == nil)
            
            // Save Button
            Button(action: onToggleSave) {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isSaved ? Color.orange : Color(.secondarySystemBackground))
                    .foregroundStyle(isSaved ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .sensoryFeedback(.impact(flexibility: .soft), trigger: isSaved)
    }
    
    private func openMessage() {
        guard let url = post.webURL else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    NavigationStack {
        PostDetailView(post: MockData.posts[0])
    }
    .environment(SavedPostsManager())
}
