import SwiftUI

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SearchViewModel()
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.hasSearched {
                    // Search Results
                    SearchResultsView(viewModel: viewModel)
                } else {
                    // Recent Searches
                    RecentSearchesView(viewModel: viewModel)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $viewModel.searchText,
                isPresented: .constant(true),
                prompt: "Search posts..."
            )
            .onSubmit(of: .search) {
                Task {
                    await viewModel.search()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
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
    @State private var selectedPost: Post?
    @State private var lastViewedPostId: Int?
    @State private var startingPostId: Int?
    
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
                            Text("\(viewModel.results.count) result\(viewModel.results.count == 1 ? "" : "s")")
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

#Preview("Empty") {
    SearchView()
}
