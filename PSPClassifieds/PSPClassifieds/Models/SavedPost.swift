import Foundation
import SwiftData

@Model
final class SavedPost {
    @Attribute(.unique) var postId: Int
    var topicId: Int?
    var created: Date?
    var subject: String?
    var body: String?
    var snippet: String?
    var senderName: String?
    var price: String?
    var savedAt: Date
    
    // Store hashtags as JSON
    var hashtagsData: Data?
    
    // Store attachments as JSON
    var attachmentsData: Data?
    
    init(from post: Post) {
        self.postId = post.id
        self.topicId = post.topicId
        self.created = post.created
        self.subject = post.subject
        self.body = post.body
        self.snippet = post.snippet
        self.senderName = post.senderName
        self.price = post.price
        self.savedAt = Date()
        
        // Encode hashtags
        self.hashtagsData = try? JSONEncoder().encode(post.hashtags)
        
        // Encode attachments
        self.attachmentsData = try? JSONEncoder().encode(post.attachments)
    }
    
    var hashtags: [Hashtag] {
        guard let data = hashtagsData else { return [] }
        return (try? JSONDecoder().decode([Hashtag].self, from: data)) ?? []
    }
    
    var attachments: [Attachment]? {
        guard let data = attachmentsData else { return nil }
        return try? JSONDecoder().decode([Attachment].self, from: data)
    }
    
    /// Convert back to Post for display
    func toPost() -> Post {
        Post(
            id: postId,
            topicId: topicId,
            created: created,
            subject: subject,
            body: body,
            snippet: snippet,
            senderName: senderName,
            hashtags: hashtags,
            attachments: attachments,
            price: price,
            isReply: nil
        )
    }
}
