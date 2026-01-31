import Foundation

@MainActor
@Observable
class FilterViewModel {
    var availableHashtags: [Hashtag] = []
    var selectedHashtags: Set<String> = []
    var dateRange: DateRange = .all
    var isLoading = false
    var error: Error?
    
    private let api = APIClient.shared
    
    enum DateRange: String, CaseIterable, Identifiable {
        case all = "All Time"
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case threeMonths = "Last 3 Months"
        
        var id: String { rawValue }
        
        var startDate: Date? {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .all:
                return nil
            case .today:
                return calendar.startOfDay(for: now)
            case .week:
                return calendar.date(byAdding: .day, value: -7, to: now)
            case .month:
                return calendar.date(byAdding: .month, value: -1, to: now)
            case .threeMonths:
                return calendar.date(byAdding: .month, value: -3, to: now)
            }
        }
        
        /// Convert a date back to the closest matching DateRange
        static func fromDate(_ date: Date?) -> DateRange {
            guard let date = date else { return .all }
            
            let calendar = Calendar.current
            let now = Date()
            let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            
            if daysDiff <= 1 {
                return .today
            } else if daysDiff <= 7 {
                return .week
            } else if daysDiff <= 31 {
                return .month
            } else if daysDiff <= 93 {
                return .threeMonths
            } else {
                return .all
            }
        }
    }
    
    var hasActiveFilters: Bool {
        !selectedHashtags.isEmpty || dateRange != .all
    }
    
    var activeFilterCount: Int {
        var count = 0
        if !selectedHashtags.isEmpty {
            count += selectedHashtags.count
        }
        if dateRange != .all {
            count += 1
        }
        return count
    }
    
    // MARK: - Load Hashtags
    
    func loadHashtags() async {
        guard availableHashtags.isEmpty else { return }
        
        isLoading = true
        error = nil
        
        do {
            availableHashtags = try await api.getHashtags()
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
    
    // MARK: - Selection
    
    func toggleHashtag(_ hashtag: Hashtag) {
        if selectedHashtags.contains(hashtag.name) {
            selectedHashtags.remove(hashtag.name)
        } else {
            selectedHashtags.insert(hashtag.name)
        }
    }
    
    func isSelected(_ hashtag: Hashtag) -> Bool {
        selectedHashtags.contains(hashtag.name)
    }
    
    func clearFilters() {
        selectedHashtags = []
        dateRange = .all
    }
    
    /// Sync filter state from external source (e.g., when hashtag tapped in detail view)
    func syncFrom(hashtags: [String], sinceDate: Date?) {
        selectedHashtags = Set(hashtags)
        dateRange = DateRange.fromDate(sinceDate)
    }
    
    // MARK: - Filter Application
    
    /// Returns hashtag filter string for API (comma-separated)
    var hashtagFilter: String? {
        guard !selectedHashtags.isEmpty else { return nil }
        return selectedHashtags.joined(separator: ",")
    }
}
