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

    func testURLMatchesWebURL() {
        let post = makePost(msgNum: 725001)
        XCTAssertEqual(post.shareContent.url, post.webURL)
    }

    func testURLIsNilWithoutMessageNumber() {
        XCTAssertNil(makePost(msgNum: nil).shareContent.url)
    }

    // MARK: - Text Fallback

    func testTextAppendsLink() {
        let post = makePost(subject: "FS: Stroller", price: "$40", msgNum: 725001)
        XCTAssertEqual(
            post.shareContent.text,
            "FS: Stroller\n$40\nhttps://groups.parkslopeparents.com/g/Classifieds/message/725001"
        )
    }

    func testTextIsMessageOnlyWithoutLink() {
        let post = makePost(subject: "FS: Stroller", price: "$40", msgNum: nil)
        XCTAssertEqual(post.shareContent.text, "FS: Stroller\n$40")
    }

    // MARK: - Helpers

    private func makePost(
        subject: String? = "Test",
        price: String? = nil,
        msgNum: Int? = nil
    ) -> Post {
        Post(
            id: 1,
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
