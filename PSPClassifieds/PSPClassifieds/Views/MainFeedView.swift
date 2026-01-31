import SwiftUI

struct MainFeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var filterViewModel = FilterViewModel()
    @State private var showSearch = false
    @State private var showFilters = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Active Filters Bar
                if viewModel.hasActiveFilters {
                    ActiveFiltersBar(
                        hashtags: viewModel.filterHashtags,
                        sinceDate: viewModel.filterSinceDate,
                        onRemoveHashtag: { hashtag in
                            Task {
                                filterViewModel.selectedHashtags.remove(hashtag)
                                await viewModel.removeHashtagFilter(hashtag)
                            }
                        },
                        onRemoveDate: {
                            Task {
                                filterViewModel.dateRange = .all
                                await viewModel.clearDateFilter()
                            }
                        },
                        onClearAll: {
                            Task {
                                filterViewModel.clearFilters()
                                await viewModel.clearFilters()
                            }
                        }
                    )
                }
                
                // Posts List
                PostsList(viewModel: viewModel)
            }
            .navigationTitle("PSP Classifieds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            showFilters = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: viewModel.hasActiveFilters 
                                    ? "line.3.horizontal.decrease.circle.fill" 
                                    : "line.3.horizontal.decrease.circle")
                                
                                if viewModel.activeFilterCount > 0 {
                                    Text("\(viewModel.activeFilterCount)")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Color.red)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        
                        Button {
                            showSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(viewModel: filterViewModel) {
                    Task {
                        await viewModel.applyFilters(
                            hashtags: filterViewModel.selectedHashtags,
                            sinceDate: filterViewModel.dateRange.startDate
                        )
                    }
                }
            }
            .onChange(of: showFilters) { _, isShowing in
                if isShowing {
                    // Sync FilterViewModel with current FeedViewModel filters
                    filterViewModel.syncFrom(hashtags: viewModel.filterHashtags, sinceDate: viewModel.filterSinceDate)
                }
            }
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
        }
        .task {
            await viewModel.loadInitialPosts()
        }
    }
}

// MARK: - Active Filters Bar
struct ActiveFiltersBar: View {
    let hashtags: [String]
    let sinceDate: Date?
    let onRemoveHashtag: (String) -> Void
    let onRemoveDate: () -> Void
    let onClearAll: () -> Void
    
    private var dateLabel: String? {
        guard let date = sinceDate else { return nil }
        let calendar = Calendar.current
        let now = Date()
        let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        
        if daysDiff <= 1 {
            return "Today"
        } else if daysDiff <= 7 {
            return "This Week"
        } else if daysDiff <= 31 {
            return "This Month"
        } else if daysDiff <= 93 {
            return "Last 3 Months"
        } else {
            return "Custom Date"
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Date filter chip
                if let label = dateLabel {
                    FilterChip(
                        label: label,
                        icon: "calendar",
                        onRemove: onRemoveDate
                    )
                }
                
                // Hashtag filter chips
                ForEach(hashtags, id: \.self) { hashtag in
                    FilterChip(
                        label: "#\(hashtag)",
                        icon: nil,
                        onRemove: { onRemoveHashtag(hashtag) }
                    )
                }
                
                // Clear all button (only if multiple filters)
                if hashtags.count + (sinceDate != nil ? 1 : 0) > 1 {
                    Button(action: onClearAll) {
                        Text("Clear All")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Filter Chip
struct FilterChip: View {
    let label: String
    let icon: String?
    let onRemove: () -> Void
    
    var body: some View {
        Button(action: onRemove) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Image(systemName: "xmark")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Posts List
struct PostsList: View {
    let viewModel: FeedViewModel
    @State private var showScrollToTop = false
    @State private var visibleIndices: Set<Int> = []
    @State private var selectedPost: Post?
    @State private var lastViewedPostId: Int?
    @State private var startingPostId: Int?
    
    private let showThreshold = 5 // Show button after scrolling past 5 posts
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                    Button {
                        selectedPost = post
                    } label: {
                        PostCardView(post: post)
                    }
                    .buttonStyle(.plain)
                    .id(post.id)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .onAppear {
                        visibleIndices.insert(index)
                        updateScrollButtonVisibility()
                        
                        if viewModel.shouldLoadMore(currentPost: post) {
                            Task {
                                await viewModel.loadMore()
                            }
                        }
                    }
                    .onDisappear {
                        visibleIndices.remove(index)
                        updateScrollButtonVisibility()
                    }
                }
                
                if viewModel.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollToTop {
                    ScrollToTopButton {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(viewModel.posts.first?.id, anchor: .top)
                        }
                        // Immediately hide when tapped
                        showScrollToTop = false
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay {
                if viewModel.posts.isEmpty && !viewModel.isLoading && !viewModel.isRefreshing {
                    if let error = viewModel.error {
                        ContentUnavailableView(
                            "Unable to Load Posts",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error.localizedDescription)
                        )
                    } else {
                        ContentUnavailableView(
                            "No Posts",
                            systemImage: "tray",
                            description: Text("No posts match your filters")
                        )
                    }
                }
            }
            .navigationDestination(item: $selectedPost) { post in
                PostPagerView(viewModel: viewModel, initialPost: post, lastViewedPostId: $lastViewedPostId)
            }
            .onChange(of: selectedPost) { oldValue, newValue in
                if let post = newValue {
                    // Entering detail view - remember starting position
                    startingPostId = post.id
                } else if oldValue != nil, let lastId = lastViewedPostId, let startId = startingPostId {
                    // Returning from detail - only scroll if moved more than 2 posts
                    let startIndex = viewModel.posts.firstIndex { $0.id == startId } ?? 0
                    let endIndex = viewModel.posts.firstIndex { $0.id == lastId } ?? 0
                    if abs(endIndex - startIndex) > 2 {
                        proxy.scrollTo(lastId, anchor: .center)
                    }
                }
            }
        }
    }
    
    private func updateScrollButtonVisibility() {
        let minVisibleIndex = visibleIndices.min() ?? 0
        let shouldShow = minVisibleIndex >= showThreshold
        
        if shouldShow != showScrollToTop {
            withAnimation(.easeInOut(duration: 0.2)) {
                showScrollToTop = shouldShow
            }
        }
    }
}

// MARK: - Scroll To Top Button
struct ScrollToTopButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(
                    Circle()
                        .fill(Color.accentColor)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainFeedView()
}
