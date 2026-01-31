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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        PlaceholderImage()
                    @unknown default:
                        PlaceholderImage()
                    }
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
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(hashtags.prefix(4)) { hashtag in
                    HashtagPill(hashtag: hashtag)
                }
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
