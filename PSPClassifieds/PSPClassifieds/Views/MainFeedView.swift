import SwiftUI

struct MainFeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var filterViewModel = FilterViewModel()
    @State private var showSearch = false
    @State private var showFilters = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Active Filters Banner
                if viewModel.hasActiveFilters {
                    ActiveFiltersBanner(
                        filterCount: viewModel.activeFilterCount,
                        onClear: {
                            Task {
                                filterViewModel.clearFilters()
                                await viewModel.clearFilters()
                            }
                        }
                    )
                }
                
                // Category Tabs
                CategoryTabBar(
                    selectedCategory: viewModel.selectedCategory,
                    onSelect: { category in
                        Task {
                            await viewModel.changeCategory(category)
                        }
                    }
                )
                
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
            .sheet(isPresented: $showSearch) {
                SearchView()
            }
        }
        .task {
            await viewModel.loadInitialPosts()
        }
    }
}

// MARK: - Active Filters Banner
struct ActiveFiltersBanner: View {
    let filterCount: Int
    let onClear: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption)
            
            Text("\(filterCount) filter\(filterCount == 1 ? "" : "s") active")
                .font(.caption)
                .fontWeight(.medium)
            
            Spacer()
            
            Button("Clear", action: onClear)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .foregroundStyle(Color.accentColor)
    }
}

// MARK: - Category Tab Bar
struct CategoryTabBar: View {
    let selectedCategory: Category
    let onSelect: (Category) -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.allCases) { category in
                    CategoryTab(
                        category: category,
                        isSelected: category == selectedCategory,
                        onTap: { onSelect(category) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct CategoryTab: View {
    let category: Category
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            Text(category.displayName)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isSelected ? .white : .primary)
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
    
    private let showThreshold = 5 // Show button after scrolling past 5 posts
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(viewModel.posts.enumerated()), id: \.element.id) { index, post in
                    NavigationLink(value: post) {
                        PostCardView(post: post)
                    }
                    .id(index)
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
                            proxy.scrollTo(0, anchor: .top)
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
                            description: Text("No posts found in this category")
                        )
                    }
                }
            }
            .navigationDestination(for: Post.self) { post in
                PostDetailView(post: post)
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
