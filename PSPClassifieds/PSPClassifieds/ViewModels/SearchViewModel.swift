import Foundation

@MainActor
@Observable
class SearchViewModel {
    var searchText = ""
    var results: [Post] = []
    var isSearching = false
    var hasSearched = false
    var error: Error?
    
    private let api = APIClient.shared
    private let recentSearchesKey = "recentSearches"
    private let maxRecentSearches = 10
    
    // MARK: - Recent Searches
    
    var recentSearches: [String] {
        get {
            UserDefaults.standard.stringArray(forKey: recentSearchesKey) ?? []
        }
        set {
            UserDefaults.standard.set(newValue, forKey: recentSearchesKey)
        }
    }
    
    func addToRecentSearches(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var searches = recentSearches
        // Remove if already exists (to move to top)
        searches.removeAll { $0.lowercased() == trimmed.lowercased() }
        // Add to beginning
        searches.insert(trimmed, at: 0)
        // Keep only max
        if searches.count > maxRecentSearches {
            searches = Array(searches.prefix(maxRecentSearches))
        }
        recentSearches = searches
    }
    
    func removeRecentSearch(_ query: String) {
        var searches = recentSearches
        searches.removeAll { $0 == query }
        recentSearches = searches
    }
    
    func clearRecentSearches() {
        recentSearches = []
    }
    
    // MARK: - Search
    
    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            hasSearched = false
            return
        }
        
        isSearching = true
        error = nil
        hasSearched = true
        
        do {
            let response = try await api.getPosts(search: query, limit: 50)
            results = response.messages
            addToRecentSearches(query)
        } catch {
            self.error = error
            results = []
        }
        
        isSearching = false
    }
    
    func searchFor(_ query: String) async {
        searchText = query
        await search()
    }
    
    func clearSearch() {
        searchText = ""
        results = []
        hasSearched = false
        error = nil
    }
}
