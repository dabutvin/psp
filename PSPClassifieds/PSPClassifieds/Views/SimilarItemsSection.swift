import SwiftUI
import os

private let similarItemsLogger = Logger(subsystem: "com.psp.classifieds", category: "SimilarItems")

// MARK: - Search Query Fallback

/// Generates fallback search queries from a base query.
/// Returns full query first, then progressively smaller chunks from front and back.
/// e.g. "A B C D E F" → ["A B C D E F", "A B C", "D E F", "A B", "E F"]
func generateSearchQueries(from query: String) -> [String] {
    let words = query.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return [] }
    
    var queries: [String] = []
    var seen: Set<String> = []
    
    func addQuery(_ q: String) {
        if !q.isEmpty && !seen.contains(q) {
            queries.append(q)
            seen.insert(q)
        }
    }
    
    // Always try full query first
    addQuery(words.joined(separator: " "))
    
    // Then progressively halve from front and back
    // e.g. 7 words: [7], [3, 4], [1-2, 3-4] (indices)
    var currentRanges: [(start: Int, count: Int)] = [(0, words.count)]
    
    while queries.count < 6 {
        var nextRanges: [(start: Int, count: Int)] = []
        var addedAny = false
        
        for range in currentRanges {
            if range.count > 2 {
                let firstHalfCount = range.count / 2
                let lastHalfCount = range.count - firstHalfCount
                
                let firstHalf = Array(words[range.start..<(range.start + firstHalfCount)]).joined(separator: " ")
                let lastHalf = Array(words[(range.start + firstHalfCount)..<(range.start + range.count)]).joined(separator: " ")
                
                addQuery(firstHalf)
                addQuery(lastHalf)
                addedAny = true
                
                nextRanges.append((range.start, firstHalfCount))
                nextRanges.append((range.start + firstHalfCount, lastHalfCount))
            }
        }
        
        if !addedAny { break }
        currentRanges = nextRanges
    }
    
    return Array(queries.prefix(6))
}

// MARK: - Search Query Extraction

/// Extracts a search query from a post subject by stripping prefixes, prices, and common noise.
/// Returns nil if the cleaned query is too short to be meaningful.
func extractSimilarSearchQuery(from subject: String?) -> String? {
    guard let subject = subject else { return nil }
    
    var cleaned = subject
    
    // Remove hashtag words (e.g. #ForSale, #BabyGear) - do this FIRST before prefix removal
    cleaned = cleaned.replacingOccurrences(
        of: #"#\w+"#,
        with: "",
        options: .regularExpression
    )
    
    // Remove parenthetical noise like (Repost), (Updated), (Price Drop), (SOLD), (Sz 8), (Size M), etc.
    cleaned = cleaned.replacingOccurrences(
        of: #"\((?:Repost|Updated|Price Drop|Sold|Pending|OBO|Sz\.?\s*\w+|Size\s*\w+)\)"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    
    // Remove common prefixes like "FS:", "FF:", "ISO:", "FREE:", "Re:", "For Sale:" anywhere they appear
    cleaned = cleaned.replacingOccurrences(
        of: #"\b(Re:\s*)?(FS|FF|ISO|FREE|ForSale|ForFree|For\s+Sale|For\s+Free)\s*:?\s*"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    
    // Remove prices (e.g. $200, $1,500, $25.00)
    cleaned = cleaned.replacingOccurrences(
        of: #"\$[\d,]+(\.\d{2})?"#,
        with: "",
        options: .regularExpression
    )
    
    // Remove size indicators that are too specific (e.g. "2T", "3T", "4T", "12M", "18M")
    cleaned = cleaned.replacingOccurrences(
        of: #"\b\d{1,2}[TM]\b"#,
        with: "",
        options: [.regularExpression, .caseInsensitive]
    )
    
    // Remove standalone numbers (e.g. "705" in "k-nex 705 piece set")
    cleaned = cleaned.replacingOccurrences(
        of: #"\b\d+\b"#,
        with: "",
        options: .regularExpression
    )
    
    // Remove separator characters (+ / | &) with surrounding spaces
    cleaned = cleaned.replacingOccurrences(
        of: #"\s*[+/|&]\s*"#,
        with: " ",
        options: .regularExpression
    )
    
    // Remove commas (always a separator)
    cleaned = cleaned.replacingOccurrences(of: ",", with: " ")
    
    // Remove dashes only when used as separators (surrounded by spaces), keep hyphens in words like "k-nex"
    cleaned = cleaned.replacingOccurrences(
        of: #"\s+[-–—]\s+"#,
        with: " ",
        options: .regularExpression
    )
    
    // Remove filler/noise words (standalone)
    let fillerWords = ["fully", "loaded", "brand", "new", "like", "great", "condition", 
                      "excellent", "good", "more", "extra", "spare", "gently", "used",
                      "barely", "never", "only", "just", "very", "super", "amazing",
                      "perfect", "mint", "euc", "nwt", "nib", "obo", "firm", "for",
                      "piece", "set", "pieces", "deal", "with", "of", "and",
                      // Number words
                      "one", "two", "three", "four", "five", "six", "seven", "eight", 
                      "nine", "ten", "pair", "dozen"]
    for word in fillerWords {
        cleaned = cleaned.replacingOccurrences(
            of: "\\b\(word)\\b",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
    
    // Remove stray punctuation left behind (leading/trailing dashes, colons, etc.)
    cleaned = cleaned.replacingOccurrences(
        of: #"^\s*[-–—:,]+|[-–—:,]+\s*$"#,
        with: "",
        options: .regularExpression
    )
    
    // Collapse whitespace and trim
    cleaned = cleaned.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    ).trimmingCharacters(in: .whitespaces)
    
    // If too short (< 3 chars), not useful for search
    guard cleaned.count >= 3 else { return nil }
    
    return cleaned
}

// MARK: - Similar Items Section
struct SimilarItemsSection: View {
    let post: Post
    @Binding var selectedSimilarPost: Post?
    @Binding var similarPostsForMore: [Post]
    @Binding var similarSearchQuery: String?
    @Binding var showMoreSimilar: Bool
    
    @State private var similarPosts: [Post] = []
    @State private var isLoading = false
    @State private var searchQuery: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !similarPosts.isEmpty {
                Text("Similar Items")
                    .font(.headline)
                    .padding(.horizontal, 20)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(similarPosts.prefix(5)) { similarPost in
                            Button {
                                selectedSimilarPost = similarPost
                            } label: {
                                SimilarItemCard(post: similarPost)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        // "More" button only if there are more than 3 results
                        if searchQuery != nil && similarPosts.count > 5 {
                            Button {
                                similarPostsForMore = similarPosts
                                similarSearchQuery = searchQuery
                                showMoreSimilar = true
                            } label: {
                                MoreButton()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .task {
            await loadSimilarItems()
        }
    }
    
    private func loadSimilarItems() async {
        guard let query = extractSimilarSearchQuery(from: post.subject) else {
            similarPosts = []
            searchQuery = nil
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let queriesToTry = generateSearchQueries(from: query)
        var attempts: [(query: String, count: Int)] = []
        
        for (index, currentQuery) in queriesToTry.enumerated() {
            do {
                let response = try await APIClient.shared.getPosts(search: currentQuery, limit: 7)
                let filtered = response.messages.filter { $0.id != post.id }
                attempts.append((currentQuery, filtered.count))
                
                // If we got at least 2 results, use them
                if filtered.count >= 2 {
                    similarItemsLogger.info("Similar items: \(attempts.map { "\"\($0.query)\"→\($0.count)" }.joined(separator: ", "))")
                    similarPosts = filtered
                    searchQuery = currentQuery
                    return
                }
                
                // If this is our last attempt, use whatever we got
                if index == queriesToTry.count - 1 {
                    similarItemsLogger.info("Similar items: \(attempts.map { "\"\($0.query)\"→\($0.count)" }.joined(separator: ", "))")
                    similarPosts = filtered
                    searchQuery = filtered.isEmpty ? nil : currentQuery
                    return
                }
            } catch {
                attempts.append((currentQuery, -1))
                similarItemsLogger.error("Similar items search failed for '\(currentQuery)': \(error.localizedDescription)")
            }
        }
        
        // If all queries failed
        similarItemsLogger.info("Similar items: \(attempts.map { "\"\($0.query)\"→\($0.count)" }.joined(separator: ", "))")
        similarPosts = []
        searchQuery = nil
    }
}

// MARK: - Similar Item Card (compact vertical)
struct SimilarItemCard: View {
    let post: Post
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            Group {
                if let url = post.firstImageURL {
                    AuthenticatedImage(url: url, contentMode: .fill) {
                        SkeletonImage()
                    } errorView: { _ in
                        PlaceholderImage()
                    }
                } else {
                    PlaceholderImage()
                }
            }
            .frame(width: 150, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Title
            Text((post.subject ?? "No Subject").decodingHTMLEntities())
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            
            // Price (or empty space to maintain alignment)
            Text(post.price ?? " ")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(post.price != nil ? .green : .clear)
            
            // Timestamp
            Text(post.relativeTimeString)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 150)
    }
}

// MARK: - More Button
struct MoreButton: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.tertiarySystemBackground))
                    .frame(width: 150, height: 110)
                
                VStack(spacing: 6) {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("More")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Spacer to align with cards that have title/price/timestamp
            Spacer(minLength: 0)
        }
        .frame(width: 150)
    }
}

// MARK: - Similar Results List View
/// A list view for showing "more" similar items (navigated from the More button)
struct SimilarResultsListView: View {
    let searchQuery: String
    let excludePostId: Int
    
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var selectedPost: Post?
    @State private var lastViewedPostId: Int?
    @State private var startingPostId: Int?
    
    private var isSubscribed: Bool {
        notificationManager.isSubscribed(to: searchQuery)
    }
    
    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if posts.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                ScrollViewReader { proxy in
                    List {
                        Section {
                            ForEach(posts) { post in
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
                                resultCount: posts.count,
                                searchText: searchQuery,
                                isSubscribed: isSubscribed,
                                onToggleSubscription: {
                                    Task {
                                        if isSubscribed {
                                            await notificationManager.unsubscribeFromSearchTerm(searchQuery)
                                        } else {
                                            await notificationManager.subscribeToSearchTerm(searchQuery)
                                        }
                                    }
                                }
                            )
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(item: $selectedPost) { post in
                        StaticPostPagerView(posts: posts, initialPost: post, lastViewedPostId: $lastViewedPostId)
                    }
                    .onChange(of: selectedPost) { oldValue, newValue in
                        if let post = newValue {
                            startingPostId = post.id
                        } else if oldValue != nil, let lastId = lastViewedPostId, let startId = startingPostId {
                            let startIndex = posts.firstIndex { $0.id == startId } ?? 0
                            let endIndex = posts.firstIndex { $0.id == lastId } ?? 0
                            if abs(endIndex - startIndex) > 2 {
                                proxy.scrollTo(lastId, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Similar to \"\(searchQuery)\"")
        .task {
            await loadResults()
        }
    }
    
    private func loadResults() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let response = try await APIClient.shared.getPosts(search: searchQuery)
            posts = response.messages.filter { $0.id != excludePostId }
        } catch {
            similarItemsLogger.error("Failed to load similar results: \(error.localizedDescription)")
            posts = []
        }
    }
}

#Preview {
    @Previewable @State var selectedSimilarPost: Post?
    @Previewable @State var similarPostsForMore: [Post] = []
    @Previewable @State var similarSearchQuery: String?
    @Previewable @State var showMoreSimilar = false
    
    NavigationStack {
        SimilarItemsSection(
            post: MockData.posts[0],
            selectedSimilarPost: $selectedSimilarPost,
            similarPostsForMore: $similarPostsForMore,
            similarSearchQuery: $similarSearchQuery,
            showMoreSimilar: $showMoreSimilar
        )
    }
}
