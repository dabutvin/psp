import Foundation

/// Device notification settings returned from the server
struct DeviceSettings: Codable {
    let token: String
    let platform: String
    let environment: String
    let searchFilters: [String]?
    let notifyAll: Bool
    let enabled: Bool
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case token, platform, environment, enabled
        case searchFilters = "search_filters"
        case notifyAll = "notify_all"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
