import Foundation

struct Attachment: Codable, Identifiable, Hashable {
    let downloadUrl: String?
    let thumbnailUrl: String?
    let filename: String?
    let mediaType: String?
    let attachmentIndex: Int?
    
    var id: String { downloadUrl ?? UUID().uuidString }
    
    // Convenience accessors for backwards compatibility
    var url: String? { downloadUrl }
    
    var imageURL: URL? {
        guard let downloadUrl else { return nil }
        return URL(string: downloadUrl)
    }
    
    var thumbnailImageURL: URL? {
        if let thumb = thumbnailUrl {
            return URL(string: thumb)
        }
        return imageURL
    }
    
    enum CodingKeys: String, CodingKey {
        case downloadUrl = "download_url"
        case thumbnailUrl = "thumbnail_url"
        case filename
        case mediaType = "media_type"
        case attachmentIndex = "attachment_index"
    }
}
