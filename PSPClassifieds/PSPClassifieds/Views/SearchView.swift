import SwiftUI

struct SearchView: View {
    @Binding var isPresented: Bool
    @State private var viewModel = SearchViewModel()
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasSearched {
                    SearchResultsView(viewModel: viewModel, notificationManager: NotificationManager.shared)
                } else {
                    RecentSearchesView(viewModel: viewModel)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inlineLarge)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        
                        TextField("Search posts...", text: $viewModel.searchText)
                            .focused($isSearchFocused)
                            .submitLabel(.search)
                            .onSubmit {
                                Task {
                                    await viewModel.search()
                                }
                            }
                        
                        if !viewModel.searchText.isEmpty {
                            Button {
                                viewModel.searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            isSearchFocused = true
        }
    }
}

// MARK: - Recent Searches View
struct RecentSearchesView: View {
    let viewModel: SearchViewModel
    
    var body: some View {
        List {
            if viewModel.recentSearches.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Recent Searches",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your search history will appear here")
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(viewModel.recentSearches, id: \.self) { query in
                        Button {
                            Task {
                                await viewModel.searchFor(query)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                                
                                Text(query)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                Image(systemName: "arrow.up.left")
                                    .foregroundStyle(.tertiary)
                                    .font(.caption)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                withAnimation {
                                    viewModel.removeRecentSearch(query)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        if !viewModel.recentSearches.isEmpty {
                            Button("Clear All") {
                                withAnimation {
                                    viewModel.clearRecentSearches()
                                }
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - Search Results View
struct SearchResultsView: View {
    let viewModel: SearchViewModel
    @ObservedObject var notificationManager: NotificationManager
    @State private var selectedPost: Post?
    @State private var lastViewedPostId: Int?
    @State private var startingPostId: Int?
    
    private var isSubscribed: Bool {
        notificationManager.isSubscribed(to: viewModel.searchText)
    }
    
    var body: some View {
        Group {
            if viewModel.isSearching {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Searching...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(viewModel.results) { post in
                                Button {
                                    selectedPost = post
                                } label: {
                                    PostCardView(post: post)
                                }
                                .buttonStyle(.plain)
                                .id(post.id)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                            }
                        } header: {
                            SearchResultsHeader(
                                resultCount: viewModel.results.count,
                                searchText: viewModel.searchText,
                                isSubscribed: isSubscribed,
                                onToggleSubscription: {
                                    Task {
                                        if isSubscribed {
                                            await notificationManager.unsubscribeFromSearchTerm(viewModel.searchText)
                                        } else {
                                            await notificationManager.subscribeToSearchTerm(viewModel.searchText)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(item: $selectedPost) { post in
                        StaticPostPagerView(posts: viewModel.results, initialPost: post, lastViewedPostId: $lastViewedPostId)
                    }
                    .onChange(of: selectedPost) { oldValue, newValue in
                        if let post = newValue {
                            startingPostId = post.id
                        } else if oldValue != nil, let lastId = lastViewedPostId, let startId = startingPostId {
                            let startIndex = viewModel.results.firstIndex { $0.id == startId } ?? 0
                            let endIndex = viewModel.results.firstIndex { $0.id == lastId } ?? 0
                            if abs(endIndex - startIndex) > 2 {
                                proxy.scrollTo(lastId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Search Results Header
struct SearchResultsHeader: View {
    let resultCount: Int
    let searchText: String
    let isSubscribed: Bool
    let onToggleSubscription: () -> Void
    
    var body: some View {
        HStack {
            Text("\(resultCount) result\(resultCount == 1 ? "" : "s")")
                .accessibilityLabel("\(resultCount) search result\(resultCount == 1 ? "" : "s")")
            
            Spacer()
            
            Button(action: onToggleSubscription) {
                HStack(spacing: 4) {
                    Image(systemName: isSubscribed ? "bell.fill" : "bell")
                        .accessibilityHidden(true)
                    Text(isSubscribed ? "Subscribed" : "Notify me")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(isSubscribed ? .blue : .secondary)
            .controlSize(.small)
            .accessibilityLabel(isSubscribed ? "Subscribed to \(searchText)" : "Subscribe to \(searchText)")
            .accessibilityHint(isSubscribed ? "Double tap to unsubscribe from notifications" : "Double tap to receive notifications for new posts matching this search")
        }
    }
}

#Preview("Empty") {
    SearchView(isPresented: .constant(true))
}
