import SwiftUI
import SwiftData

struct SavedPostsView: View {
    @Environment(SavedPostsManager.self) private var savedPostsManager
    @State private var savedPosts: [Post] = []
    @State private var isLoading = true
    @State private var selectedPost: Post?
    @State private var lastViewedPostId: Int?
    @State private var startingPostId: Int?
    
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
            .navigationDestination(item: $selectedPost) { post in
                StaticPostPagerView(posts: savedPosts, initialPost: post, lastViewedPostId: $lastViewedPostId)
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
        ScrollViewReader { proxy in
            List {
                ForEach(savedPosts) { post in
                    Button {
                        selectedPost = post
                    } label: {
                        PostCardView(post: post)
                    }
                    .buttonStyle(.plain)
                    .id(post.id)
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
            .onChange(of: selectedPost) { oldValue, newValue in
                if let post = newValue {
                    startingPostId = post.id
                } else if oldValue != nil, let lastId = lastViewedPostId, let startId = startingPostId {
                    let startIndex = savedPosts.firstIndex { $0.id == startId } ?? 0
                    let endIndex = savedPosts.firstIndex { $0.id == lastId } ?? 0
                    if abs(endIndex - startIndex) > 2 {
                        proxy.scrollTo(lastId, anchor: .center)
                    }
                }
            }
        }
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
