import SwiftUI

struct HashtagPill: View {
    let hashtag: Hashtag
    var size: Size = .regular
    var onTap: (() -> Void)? = nil
    
    enum Size {
        case small, regular
        
        var font: Font {
            switch self {
            case .small: return .caption2
            case .regular: return .caption
            }
        }
        
        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 6
            case .regular: return 8
            }
        }
        
        var verticalPadding: CGFloat {
            switch self {
            case .small: return 3
            case .regular: return 4
            }
        }
    }
    
    var body: some View {
        Group {
            if let onTap = onTap {
                Button(action: onTap) {
                    pillContent
                }
                .buttonStyle(.plain)
            } else {
                pillContent
            }
        }
    }
    
    private var pillContent: some View {
        Text("#\(hashtag.name)")
            .font(size.font)
            .fontWeight(.medium)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(hashtag.color.opacity(0.15))
            .foregroundStyle(hashtag.color)
            .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack {
            HashtagPill(hashtag: Hashtag(name: "ForSale", colorHex: "#4CAF50", count: nil))
            HashtagPill(hashtag: Hashtag(name: "NorthSlope", colorHex: "#9C27B0", count: nil))
            HashtagPill(hashtag: Hashtag(name: "BabyGear", colorHex: "#00BCD4", count: nil))
        }
        
        HStack {
            HashtagPill(hashtag: Hashtag(name: "ForSale", colorHex: "#4CAF50", count: nil), size: .small)
            HashtagPill(hashtag: Hashtag(name: "NorthSlope", colorHex: "#9C27B0", count: nil), size: .small)
        }
    }
    .padding()
}
