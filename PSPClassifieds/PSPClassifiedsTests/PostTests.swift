import XCTest
@testable import PSPClassifieds

final class PostTests: XCTestCase {

    // MARK: - Category Detection

    func testCategoryForSale() {
        let post = makePost(hashtags: [Hashtag(name: "ForSale", colorHex: nil, count: nil)])
        XCTAssertEqual(post.category, .forSale)
    }

    func testCategoryForFree() {
        let post = makePost(hashtags: [Hashtag(name: "ForFree", colorHex: nil, count: nil)])
        XCTAssertEqual(post.category, .forFree)
    }

    func testCategoryISO() {
        let post = makePost(hashtags: [Hashtag(name: "ISO", colorHex: nil, count: nil)])
        XCTAssertEqual(post.category, .iso)
    }

    func testCategoryDefaultsToAll() {
        let post = makePost(hashtags: [Hashtag(name: "Furniture", colorHex: nil, count: nil)])
        XCTAssertEqual(post.category, .all)
    }

    func testCategoryCaseInsensitive() {
        let post = makePost(hashtags: [Hashtag(name: "forsale", colorHex: nil, count: nil)])
        XCTAssertEqual(post.category, .forSale)
    }

    // MARK: - Web URL

    func testWebURL() {
        let post = makePost(msgNum: 12345)
        XCTAssertEqual(
            post.webURL,
            URL(string: "https://groups.parkslopeparents.com/g/Classifieds/message/12345")
        )
    }

    func testWebURLNilWhenNoMsgNum() {
        let post = makePost(msgNum: nil)
        XCTAssertNil(post.webURL)
    }

    // MARK: - JSON Decoding

    func testDecodesFromJSON() throws {
        let json = """
        {
            "id": 1,
            "topic_id": 100,
            "subject": "Selling a stroller",
            "snippet": "Great condition",
            "name": "Jane",
            "msg_num": 555,
            "hashtags": [{"name": "ForSale", "color_hex": "#FF0000"}],
            "attachments": [],
            "is_reply": false
        }
        """
        let data = Data(json.utf8)
        let post = try JSONDecoder().decode(Post.self, from: data)

        XCTAssertEqual(post.id, 1)
        XCTAssertEqual(post.topicId, 100)
        XCTAssertEqual(post.subject, "Selling a stroller")
        XCTAssertEqual(post.senderName, "Jane")
        XCTAssertEqual(post.msgNum, 555)
        XCTAssertEqual(post.hashtags.first?.name, "ForSale")
        XCTAssertEqual(post.isReply, false)
    }

    // MARK: - HTML Decoding

    func testHTMLEntityDecoding() {
        let input = "Books &amp; Toys &lt;3"
        XCTAssertEqual(input.decodingHTMLEntities(), "Books & Toys <3")
    }

    func testHTMLNumericEntityDecoding() {
        let input = "it&#39;s great"
        XCTAssertEqual(input.decodingHTMLEntities(), "it's great")
    }

    // MARK: - Attachment URL Handling

    func testAttachmentFullURL() {
        let attachment = Attachment(
            downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/123/0/photo.jpg",
            thumbnailUrl: nil,
            filename: "photo.jpg",
            mediaType: "image/jpeg",
            attachmentIndex: 0
        )
        XCTAssertEqual(
            attachment.imageURL,
            URL(string: "https://groups.parkslopeparents.com/g/Classifieds/attachment/123/0/photo.jpg")
        )
    }

    func testAttachmentRelativeURL() {
        let attachment = Attachment(
            downloadUrl: "/attachment/722075/0",
            thumbnailUrl: nil,
            filename: "photo.jpg",
            mediaType: "image/jpeg",
            attachmentIndex: 0
        )
        XCTAssertEqual(
            attachment.imageURL,
            URL(string: "https://groups.parkslopeparents.com/g/Classifieds/attachment/722075/0")
        )
    }

    func testAttachmentThumbnailRelativeURL() {
        let attachment = Attachment(
            downloadUrl: "/attachment/722075/0",
            thumbnailUrl: "/attachment/722075/0?thumb=1",
            filename: "photo.jpg",
            mediaType: "image/jpeg",
            attachmentIndex: 0
        )
        XCTAssertEqual(
            attachment.thumbnailImageURL,
            URL(string: "https://groups.parkslopeparents.com/g/Classifieds/attachment/722075/0?thumb=1")
        )
    }

    func testAttachmentNilURL() {
        let attachment = Attachment(
            downloadUrl: nil,
            thumbnailUrl: nil,
            filename: nil,
            mediaType: nil,
            attachmentIndex: nil
        )
        XCTAssertNil(attachment.imageURL)
        XCTAssertNil(attachment.thumbnailImageURL)
    }

    // MARK: - Helpers

    private func makePost(
        id: Int = 1,
        hashtags: [Hashtag] = [],
        msgNum: Int? = nil
    ) -> Post {
        Post(
            id: id,
            topicId: nil,
            created: nil,
            subject: "Test",
            body: nil,
            snippet: nil,
            senderName: nil,
            msgNum: msgNum,
            hashtags: hashtags,
            attachments: nil,
            price: nil,
            isReply: nil
        )
    }
}
