import Foundation

struct Attachment: Codable, Identifiable, Hashable {
    let url: String
    let thumbnailUrl: String?
    
    var id: String { url }
    
    var imageURL: URL? {
        URL(string: url)
    }
    
    var thumbnailImageURL: URL? {
        guard let thumb = thumbnailUrl else { return imageURL }
        return URL(string: thumb)
    }
    
    enum CodingKeys: String, CodingKey {
        case url
        case thumbnailUrl = "thumbnail_url"
    }
}
