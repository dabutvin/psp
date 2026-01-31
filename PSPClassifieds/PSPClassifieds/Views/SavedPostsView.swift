import SwiftUI
import SwiftData

struct SavedPostsView: View {
    @Environment(SavedPostsManager.self) private var savedPostsManager
    @State private var savedPosts: [Post] = []
    @State private var isLoading = true
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if savedPosts.isEmpty {
                    emptyState
                } else {
                    savedPostsList
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Post.self) { post in
                PostDetailView(post: post)
            }
        }
        .onAppear {
            loadSavedPosts()
        }
        .onChange(of: savedPostsManager.savedPostIds) {
            loadSavedPosts()
        }
    }
    
    private var emptyState: some View {
        ContentUnavailableView(
            "No Saved Posts",
            systemImage: "bookmark",
            description: Text("Posts you save will appear here")
        )
    }
    
    private var savedPostsList: some View {
        List {
            ForEach(savedPosts) { post in
                NavigationLink(value: post) {
                    PostCardView(post: post)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        withAnimation {
                            savedPostsManager.unsave(post)
                        }
                    } label: {
                        Label("Unsave", systemImage: "bookmark.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func loadSavedPosts() {
        savedPosts = savedPostsManager.getAllSavedPosts()
        isLoading = false
    }
}

#Preview {
    SavedPostsView()
        .environment(SavedPostsManager())
}
