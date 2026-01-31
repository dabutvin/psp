import SwiftUI

struct PostDetailView: View {
    let post: Post
    @Environment(SavedPostsManager.self) private var savedPostsManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Image Gallery
                if let attachments = post.attachments, !attachments.isEmpty {
                    ImageGallery(attachments: attachments)
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
                    HTMLTextView(html: post.body)
                    
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
            Text(post.subject)
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
            Label(post.senderName, systemImage: "person.circle")
                .font(.subheadline)
            
            Label(post.created.formatted(date: .long, time: .shortened), systemImage: "calendar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                AsyncImage(url: attachment.imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    case .failure:
                        VStack {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.tertiary)
                            Text("Failed to load image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 300)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - HTML Text View
struct HTMLTextView: View {
    let html: String
    
    var body: some View {
        Text(attributedString)
            .font(.body)
    }
    
    private var attributedString: AttributedString {
        let stripped = html
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n\n")
            .replacingOccurrences(of: "</li>", with: "\n")
            .replacingOccurrences(of: "<li>", with: "• ")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return AttributedString(stripped)
    }
}

// MARK: - Action Buttons
struct ActionButtons: View {
    let post: Post
    let isSaved: Bool
    let onToggleSave: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Email Button
            Button {
                sendEmail()
            } label: {
                Label("Email", systemImage: "envelope")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
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
    
    private func sendEmail() {
        let subject = "Re: \(post.subject)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:?subject=\(encodedSubject)") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    NavigationStack {
        PostDetailView(post: MockData.posts[0])
    }
    .environment(SavedPostsManager())
}
