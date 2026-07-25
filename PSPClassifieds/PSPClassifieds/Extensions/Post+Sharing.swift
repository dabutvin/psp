import Foundation

/// What gets handed to the system share sheet for a post: a headline, a short
/// body that destinations like Messages and Mail pre-fill, and the groups.io link.
struct PostShareContent: Equatable {
    let title: String
    let message: String
    let url: URL?

    /// Single-string form for destinations that only accept text.
    var text: String {
        guard let url else { return message }
        return "\(message)\n\(url.absoluteString)"
    }
}

extension Post {
    var shareContent: PostShareContent {
        PostShareContent(title: shareTitle, message: shareMessage, url: webURL)
    }

    /// Subject line, HTML-decoded, with a fallback for posts that have no subject.
    var shareTitle: String {
        let decoded = (subject ?? "")
            .decodingHTMLEntities()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? "PSP Classifieds post" : decoded
    }

    /// Kept to a couple of short lines so it reads well as an iMessage draft
    /// sitting above the shared link.
    private var shareMessage: String {
        var lines = [shareTitle]

        if let price = price?.trimmingCharacters(in: .whitespacesAndNewlines), !price.isEmpty {
            lines.append(price)
        }

        return lines.joined(separator: "\n")
    }
}
