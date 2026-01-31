import SwiftUI

struct MainFeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var showSearch = false
    @State private var showFilters = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            Image(systemName: "line.3.horizontal.decrease.circle")
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
                FilterSheet()
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

// MARK: - Placeholder Views
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Hashtags") {
                    Text("Coming in Phase 2")
                        .foregroundStyle(.secondary)
                }
                
                Section("Price Range") {
                    Text("Coming in Phase 2")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section("Recent Searches") {
                    Text("Coming in Phase 2")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search posts...")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    MainFeedView()
}
