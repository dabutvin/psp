import SwiftUI

struct PostCardView: View {
    let post: Post
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            PostThumbnail(url: post.firstImageURL)
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title
                Text(post.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                
                // Price (if available)
                if let price = post.price {
                    Text(price)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }
                
                // Hashtags
                HashtagRow(hashtags: post.hashtags)
                
                // Timestamp
                Text(post.relativeTimeString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Thumbnail
struct PostThumbnail: View {
    let url: URL?
    
    var body: some View {
        Group {
            if let url = url {
                // Use AuthenticatedImage for groups.parkslopeparents.com images
                AuthenticatedImage(url: url, contentMode: .fill) {
                    ProgressView()
                } errorView: { _ in
                    PlaceholderImage()
                }
            } else {
                PlaceholderImage()
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct PlaceholderImage: View {
    var body: some View {
        Rectangle()
            .fill(Color(.tertiarySystemBackground))
            .overlay {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
    }
}

// MARK: - Hashtag Row
struct HashtagRow: View {
    let hashtags: [Hashtag]
    var maxVisible: Int = 2
    
    private var visibleHashtags: [Hashtag] {
        Array(hashtags.prefix(maxVisible))
    }
    
    private var remainingCount: Int {
        max(0, hashtags.count - maxVisible)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(visibleHashtags) { hashtag in
                HashtagPill(hashtag: hashtag)
            }
            
            if remainingCount > 0 {
                Text("+\(remainingCount)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    VStack {
        PostCardView(post: MockData.posts[0])
        PostCardView(post: MockData.posts[2])
    }
    .padding()
}
