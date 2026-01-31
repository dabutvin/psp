import Foundation

enum Category: String, CaseIterable, Identifiable {
    case all = ""
    case forSale = "ForSale"
    case forFree = "ForFree"
    case iso = "ISO"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .forSale: return "For Sale"
        case .forFree: return "For Free"
        case .iso: return "ISO"
        }
    }
    
    var hashtag: String? {
        switch self {
        case .all: return nil
        case .forSale: return "ForSale"
        case .forFree: return "ForFree"
        case .iso: return "ISO"
        }
    }
}
