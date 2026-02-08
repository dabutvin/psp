import Foundation

struct Attachment: Codable, Identifiable, Hashable {
    let downloadUrl: String?
    let thumbnailUrl: String?
    let filename: String?
    let mediaType: String?
    let attachmentIndex: Int?
    
    private static let baseURL = "https://groups.parkslopeparents.com/g/Classifieds"
    
    var id: String { downloadUrl ?? UUID().uuidString }
    
    // Convenience accessors for backwards compatibility
    var url: String? { downloadUrl }
    
    /// Converts a URL string to a full URL, handling relative paths
    private func makeURL(from urlString: String?) -> URL? {
        guard let urlString else { return nil }
        
        // If it's already a full URL, use it directly
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            return URL(string: urlString)
        }
        
        // Handle relative paths by prepending base URL
        if urlString.hasPrefix("/") {
            return URL(string: Self.baseURL + urlString)
        }
        
        return URL(string: urlString)
    }
    
    var imageURL: URL? {
        makeURL(from: downloadUrl)
    }
    
    var thumbnailImageURL: URL? {
        makeURL(from: thumbnailUrl) ?? imageURL
    }
    
    enum CodingKeys: String, CodingKey {
        case downloadUrl = "download_url"
        case thumbnailUrl = "thumbnail_url"
        case filename
        case mediaType = "media_type"
        case attachmentIndex = "attachment_index"
    }
}
