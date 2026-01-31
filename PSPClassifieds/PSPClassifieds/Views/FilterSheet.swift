import SwiftUI

struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: FilterViewModel
    let onApply: () -> Void
    
    var body: some View {
        NavigationStack {
            filterList
                .listStyle(.insetGrouped)
                .navigationTitle("Filters")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Reset") {
                            withAnimation {
                                viewModel.clearFilters()
                            }
                        }
                        .disabled(!viewModel.hasActiveFilters)
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Apply") {
                            onApply()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.loadHashtags()
        }
    }
    
    private var filterList: some View {
        List {
            hashtagsSection
            dateRangeSection
        }
    }
    
    private var hashtagsSection: some View {
        Section {
            hashtagsContent
        } header: {
            hashtagsSectionHeader
        }
    }
    
    @ViewBuilder
    private var hashtagsContent: some View {
        if viewModel.isLoading {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
        } else if viewModel.availableHashtags.isEmpty {
            Text("No hashtags available")
                .foregroundStyle(.secondary)
        } else {
            HashtagFilterGrid(viewModel: viewModel)
        }
    }
    
    private var hashtagsSectionHeader: some View {
        HStack {
            Text("Hashtags")
            Spacer()
            if !viewModel.selectedHashtags.isEmpty {
                Text("\(viewModel.selectedHashtags.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
            }
        }
    }
    
    private var dateRangeSection: some View {
        Section("Date Range") {
            ForEach(FilterViewModel.DateRange.allCases) { range in
                DateRangeRow(
                    range: range,
                    isSelected: viewModel.dateRange == range,
                    onTap: {
                        withAnimation(.spring(response: 0.3)) {
                            viewModel.dateRange = range
                        }
                    }
                )
            }
        }
    }
}

// MARK: - Date Range Row
struct DateRangeRow: View {
    let range: FilterViewModel.DateRange
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(range.rawValue)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Hashtag Filter Grid
struct HashtagFilterGrid: View {
    let viewModel: FilterViewModel
    
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 8)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(viewModel.availableHashtags) { hashtag in
                HashtagFilterChip(
                    hashtag: hashtag,
                    isSelected: viewModel.isSelected(hashtag),
                    onTap: { viewModel.toggleHashtag(hashtag) }
                )
            }
        }
        .padding(.vertical, 4)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }
}

// MARK: - Hashtag Filter Chip
struct HashtagFilterChip: View {
    let hashtag: Hashtag
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            chipContent
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
    
    private var chipContent: some View {
        HStack(spacing: 4) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            
            Text("#\(hashtag.name)")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(chipBackground)
        .foregroundStyle(chipForeground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .animation(.spring(response: 0.3), value: isSelected)
    }
    
    private var chipBackground: Color {
        isSelected ? hashtag.color : hashtag.color.opacity(0.15)
    }
    
    private var chipForeground: Color {
        isSelected ? .white : hashtag.color
    }
}

#Preview {
    FilterSheet(viewModel: FilterViewModel()) {
        print("Applied filters")
    }
}
