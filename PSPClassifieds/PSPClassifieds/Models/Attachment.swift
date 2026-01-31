import Foundation

struct Attachment: Codable, Identifiable, Hashable {
    let downloadUrl: String
    let thumbnailUrl: String?
    let filename: String?
    let mediaType: String?
    let attachmentIndex: Int?
    
    var id: String { downloadUrl }
    
    // Convenience accessors for backwards compatibility
    var url: String { downloadUrl }
    
    var imageURL: URL? {
        URL(string: downloadUrl)
    }
    
    var thumbnailImageURL: URL? {
        guard let thumb = thumbnailUrl else { return imageURL }
        return URL(string: thumb)
    }
    
    enum CodingKeys: String, CodingKey {
        case downloadUrl = "download_url"
        case thumbnailUrl = "thumbnail_url"
        case filename
        case mediaType = "media_type"
        case attachmentIndex = "attachment_index"
    }
}
