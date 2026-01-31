import Foundation
import SwiftUI

struct Hashtag: Codable, Identifiable, Hashable {
    let name: String
    let colorHex: String?
    let count: Int?
    
    var id: String { name }
    
    enum CodingKeys: String, CodingKey {
        case name
        case colorHex = "color_hex"
        case count
    }
    
    var color: Color {
        guard let hex = colorHex else { return .gray }
        return Color(hex: hex) ?? .gray
    }
}

// MARK: - Hashtags API Response
struct HashtagsResponse: Codable {
    let hashtags: [Hashtag]
    let totalUnique: Int
    
    enum CodingKeys: String, CodingKey {
        case hashtags
        case totalUnique = "total_unique"
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }
        
        let length = hexSanitized.count
        switch length {
        case 6:
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8:
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }
}
