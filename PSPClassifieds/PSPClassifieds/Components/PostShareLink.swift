import SwiftUI

/// Opens the system share sheet for a post. The sheet's top row surfaces recent
/// conversations, so a post can be sent straight into an iMessage thread.
struct PostShareLink: View {
    /// Where the share affordance is being placed, which decides how it looks.
    enum Style {
        case icon
        case actionButton
        case menuItem
    }

    let post: Post
    var style: Style = .icon

    private var content: PostShareContent { post.shareContent }

    var body: some View {
        // Sharing the link lets Messages render a link bubble; posts without a
        // message number have no link, so they go out as text.
        if let url = content.url {
            ShareLink(
                item: url,
                subject: Text(content.title),
                message: Text(content.message),
                preview: SharePreview(content.title)
            ) {
                label
            }
        } else {
            ShareLink(
                item: content.text,
                subject: Text(content.title),
                message: Text(content.message),
                preview: SharePreview(content.title)
            ) {
                label
            }
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .icon:
            Image(systemName: "square.and.arrow.up")
        case .actionButton:
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(.primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        case .menuItem:
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PostShareLink(post: MockData.posts[0])

        PostShareLink(post: MockData.posts[0], style: .actionButton)

        Menu("Menu") {
            PostShareLink(post: MockData.posts[0], style: .menuItem)
        }
    }
    .padding()
}
