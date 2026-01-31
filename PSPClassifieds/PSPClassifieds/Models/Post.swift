import Foundation

struct Post: Identifiable, Codable, Hashable {
    let id: Int
    let topicId: Int?
    let created: Date?
    let subject: String?
    let body: String?
    let snippet: String?
    let senderName: String?
    let msgNum: Int?
    let hashtags: [Hashtag]
    let attachments: [Attachment]?
    let price: String?
    let isReply: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case topicId = "topic_id"
        case created
        case subject
        case body
        case snippet
        case senderName = "name"
        case msgNum = "msg_num"
        case hashtags
        case attachments
        case price
        case isReply = "is_reply"
    }
    
    /// URL to view this message on groups.io
    var webURL: URL? {
        guard let msgNum = msgNum else { return nil }
        return URL(string: "https://groups.parkslopeparents.com/g/Classifieds/message/\(msgNum)")
    }
    
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
        // First check attachments
        if let urlString = attachments?.first?.thumbnailUrl ?? attachments?.first?.url {
            return URL(string: urlString)
        }
        
        // Fall back to inline images in body HTML
        if let body = body, let inlineUrl = extractFirstInlineImage(from: body) {
            return URL(string: inlineUrl)
        }
        
        return nil
    }
    
    /// Extract the first image URL from HTML img tags
    private func extractFirstInlineImage(from html: String) -> String? {
        let imgPattern = #"<img\s+[^>]*src\s*=\s*["']([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: imgPattern, options: .caseInsensitive) else {
            return nil
        }
        
        let nsString = html as NSString
        guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: nsString.length)),
              match.numberOfRanges >= 2 else {
            return nil
        }
        
        return nsString.substring(with: match.range(at: 1))
    }
    
    var relativeTimeString: String {
        guard let created = created else { return "" }
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
