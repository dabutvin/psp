import XCTest
@testable import PSPClassifieds

final class PostSharingTests: XCTestCase {

    // MARK: - Title

    func testTitleDecodesHTMLEntities() {
        let post = makePost(subject: "FS: Books &amp; Toys")
        XCTAssertEqual(post.shareContent.title, "FS: Books & Toys")
    }

    func testTitleTrimsWhitespace() {
        let post = makePost(subject: "  FS: Stroller\n")
        XCTAssertEqual(post.shareContent.title, "FS: Stroller")
    }

    func testTitleFallsBackWhenSubjectMissing() {
        XCTAssertEqual(makePost(subject: nil).shareContent.title, "PSP Classifieds post")
        XCTAssertEqual(makePost(subject: "   ").shareContent.title, "PSP Classifieds post")
    }

    // MARK: - Message

    func testMessageIncludesPrice() {
        let post = makePost(subject: "FS: Stroller", price: "$40")
        XCTAssertEqual(post.shareContent.message, "FS: Stroller\n$40")
    }

    func testMessageOmitsMissingOrBlankPrice() {
        XCTAssertEqual(makePost(subject: "ISO: Crib").shareContent.message, "ISO: Crib")
        XCTAssertEqual(makePost(subject: "ISO: Crib", price: " ").shareContent.message, "ISO: Crib")
    }

    // MARK: - URL

    func testURLIsAppLink() {
        let post = makePost(id: 4242, msgNum: 725001)
        XCTAssertEqual(post.shareContent.url, URL(string: "https://psp-api.fly.dev/p/4242"))
    }

    // MARK: - Text Fallback

    func testTextAppendsLink() {
        let post = makePost(id: 4242, subject: "FS: Stroller", price: "$40")
        XCTAssertEqual(
            post.shareContent.text,
            "FS: Stroller\n$40\nhttps://psp-api.fly.dev/p/4242"
        )
    }

    // MARK: - Incoming Links

    func testParsesPostIdFromSharedLink() {
        let url = URL(string: "https://psp-api.fly.dev/p/4242")!
        XCTAssertEqual(PostLink.postId(from: url), 4242)
    }

    func testParsesPostIdRoundTrip() {
        let post = makePost(id: 725001)
        XCTAssertEqual(PostLink.postId(from: post.shareContent.url!), post.id)
    }

    func testRejectsOtherHosts() {
        let url = URL(string: "https://example.com/p/4242")!
        XCTAssertNil(PostLink.postId(from: url))
    }

    func testRejectsOtherPaths() {
        for path in ["/", "/p", "/p/4242/extra", "/api/v1/messages/4242", "/pp/4242"] {
            let url = URL(string: "https://psp-api.fly.dev\(path)")!
            XCTAssertNil(PostLink.postId(from: url), "Expected \(path) to be rejected")
        }
    }

    func testRejectsNonNumericPostId() {
        let url = URL(string: "https://psp-api.fly.dev/p/not-a-number")!
        XCTAssertNil(PostLink.postId(from: url))
    }

    // MARK: - Helpers

    private func makePost(
        id: Int = 1,
        subject: String? = "Test",
        price: String? = nil,
        msgNum: Int? = nil
    ) -> Post {
        Post(
            id: id,
            topicId: nil,
            created: nil,
            subject: subject,
            body: nil,
            snippet: nil,
            senderName: "Jane",
            msgNum: msgNum,
            hashtags: [],
            attachments: nil,
            price: price,
            isReply: nil
        )
    }
}
