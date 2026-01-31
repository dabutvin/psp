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
    
    var body: some View {
        List {
            ForEach(viewModel.posts) { post in
                NavigationLink(value: post) {
                    PostCardView(post: post)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .onAppear {
                    if viewModel.shouldLoadMore(currentPost: post) {
                        Task {
                            await viewModel.loadMore()
                        }
                    }
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
        .overlay {
            if viewModel.posts.isEmpty && !viewModel.isLoading && !viewModel.isRefreshing {
                ContentUnavailableView(
                    "No Posts",
                    systemImage: "tray",
                    description: Text("No posts found in this category")
                )
            }
        }
        .navigationDestination(for: Post.self) { post in
            PostDetailView(post: post)
        }
    }
}

#Preview {
    MainFeedView()
}
