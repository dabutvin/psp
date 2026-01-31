import Foundation

struct Post: Identifiable, Codable, Hashable {
    let id: Int
    let topicId: Int
    let created: Date
    let subject: String
    let body: String
    let snippet: String
    let senderName: String
    let hashtags: [Hashtag]
    let attachments: [Attachment]?
    let price: String?
    
    var category: Category {
        if hashtags.contains(where: { $0.name.lowercased() == "forsale" }) {
            return .forSale
        } else if hashtags.contains(where: { $0.name.lowercased() == "forfree" }) {
            return .forFree
        } else if hashtags.contains(where: { $0.name.lowercased() == "iso" }) {
            return .iso
        }
        return .all
    }
    
    var firstImageURL: URL? {
        guard let urlString = attachments?.first?.thumbnailUrl ?? attachments?.first?.url else {
            return nil
        }
        return URL(string: urlString)
    }
    
    var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: created, relativeTo: Date())
    }
    
    // Hashable based on id only
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Post, rhs: Post) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - API Response
struct PostsResponse: Codable {
    let messages: [Post]
    let nextCursor: String?
    let hasMore: Bool
    
    enum CodingKeys: String, CodingKey {
        case messages
        case nextCursor = "next_cursor"
        case hasMore = "has_more"
    }
}
