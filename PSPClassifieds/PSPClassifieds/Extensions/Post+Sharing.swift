import Foundation

/// Links that open a post in this app. The backend serves an
/// apple-app-site-association file covering `/p/*`, which makes these universal
/// links: tapping one opens the app when it's installed, and falls back to the
/// backend's web page (which links through to groups.io) when it isn't.
enum PostLink {
    static let host = "psp-api.fly.dev"

    static func url(postId: Int) -> URL? {
        URL(string: "https://\(host)/p/\(postId)")
    }

    /// The post id carried by an incoming universal link, or nil if the URL is
    /// not one of ours.
    static func postId(from url: URL) -> Int? {
        guard url.host?.lowercased() == host else { return nil }

        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2, components[0] == "p" else { return nil }

        return Int(components[1])
    }
}

/// What gets handed to the system share sheet for a post: a headline, a short
/// body that destinations like Messages and Mail pre-fill, and the link that
/// opens the post in the app.
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
        PostShareContent(title: shareTitle, message: shareMessage, url: PostLink.url(postId: id))
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
