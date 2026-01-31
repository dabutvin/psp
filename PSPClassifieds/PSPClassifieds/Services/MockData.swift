import Foundation

enum MockData {
    static let hashtags: [Hashtag] = [
        Hashtag(name: "ForSale", colorHex: "#4CAF50"),
        Hashtag(name: "ForFree", colorHex: "#2196F3"),
        Hashtag(name: "ISO", colorHex: "#FF9800"),
        Hashtag(name: "NorthSlope", colorHex: "#9C27B0"),
        Hashtag(name: "SouthSlope", colorHex: "#E91E63"),
        Hashtag(name: "BabyGear", colorHex: "#00BCD4"),
        Hashtag(name: "Toddler", colorHex: "#FFEB3B"),
        Hashtag(name: "Kids", colorHex: "#FF5722")
    ]
    
    static let posts: [Post] = [
        Post(
            id: 1,
            topicId: 1001,
            created: Date().addingTimeInterval(-3600),
            subject: "FS: Size 6 Adidas Kids Sneakers Bundle",
            body: """
            <p>Hi PSP,</p>
            <p>Selling a bundle of 5 pairs of gently used Adidas sneakers, all size 6 toddler. 
            Great condition, minimal wear. Perfect for an active kiddo!</p>
            <p>Includes:</p>
            <ul>
                <li>2x Adidas Superstar (white/black)</li>
                <li>2x Adidas Gazelle (navy, red)</li>
                <li>1x Adidas Stan Smith (white/green)</li>
            </ul>
            <p>Pick up in North Slope, near 5th Ave & Union.</p>
            <p>Thanks!</p>
            """,
            snippet: "Selling a bundle of 5 pairs of gently used Adidas sneakers, all size 6 toddler...",
            senderName: "Claire Bourgeois",
            hashtags: [
                Hashtag(name: "ForSale", colorHex: "#4CAF50"),
                Hashtag(name: "NorthSlope", colorHex: "#9C27B0"),
                Hashtag(name: "Toddler", colorHex: "#FFEB3B")
            ],
            attachments: [
                Attachment(url: "https://example.com/shoes1.jpg", thumbnailUrl: "https://example.com/shoes1_thumb.jpg"),
                Attachment(url: "https://example.com/shoes2.jpg", thumbnailUrl: "https://example.com/shoes2_thumb.jpg")
            ],
            price: "$40"
        ),
        Post(
            id: 2,
            topicId: 1002,
            created: Date().addingTimeInterval(-7200),
            subject: "FREE: Baby Bjorn Bouncer",
            body: """
            <p>Moving and need this gone ASAP!</p>
            <p>Baby Bjorn bouncer in good condition. Some wear on the fabric but fully functional. 
            My kids loved this thing.</p>
            <p>Pickup only - 7th Ave near 9th St.</p>
            """,
            snippet: "Moving and need this gone ASAP! Baby Bjorn bouncer in good condition...",
            senderName: "Michael Torres",
            hashtags: [
                Hashtag(name: "ForFree", colorHex: "#2196F3"),
                Hashtag(name: "BabyGear", colorHex: "#00BCD4")
            ],
            attachments: [
                Attachment(url: "https://example.com/bouncer.jpg", thumbnailUrl: "https://example.com/bouncer_thumb.jpg")
            ],
            price: nil
        ),
        Post(
            id: 3,
            topicId: 1003,
            created: Date().addingTimeInterval(-86400),
            subject: "ISO: Double Stroller (Bob or similar)",
            body: """
            <p>Looking for a double jogging stroller, preferably Bob Revolution Duallie or similar quality.</p>
            <p>Happy to pay fair price for good condition. Can pick up anywhere in Park Slope.</p>
            <p>Thanks neighbors!</p>
            """,
            snippet: "Looking for a double jogging stroller, preferably Bob Revolution Duallie...",
            senderName: "Sarah Kim",
            hashtags: [
                Hashtag(name: "ISO", colorHex: "#FF9800"),
                Hashtag(name: "BabyGear", colorHex: "#00BCD4")
            ],
            attachments: nil,
            price: nil
        ),
        Post(
            id: 4,
            topicId: 1004,
            created: Date().addingTimeInterval(-172800),
            subject: "FS: Pottery Barn Kids Bookshelf - White",
            body: """
            <p>Beautiful white Pottery Barn Kids bookshelf. Perfect for a nursery or kids room.</p>
            <p>Dimensions: 36"W x 48"H x 12"D</p>
            <p>A few minor scuffs but overall excellent condition. Retails for $400+.</p>
            <p>Cash only, must pick up. We're near Prospect Park West.</p>
            """,
            snippet: "Beautiful white Pottery Barn Kids bookshelf. Perfect for a nursery or kids room...",
            senderName: "Jennifer Walsh",
            hashtags: [
                Hashtag(name: "ForSale", colorHex: "#4CAF50"),
                Hashtag(name: "Kids", colorHex: "#FF5722")
            ],
            attachments: [
                Attachment(url: "https://example.com/bookshelf.jpg", thumbnailUrl: "https://example.com/bookshelf_thumb.jpg")
            ],
            price: "$150"
        ),
        Post(
            id: 5,
            topicId: 1005,
            created: Date().addingTimeInterval(-259200),
            subject: "FREE: Outgrown Kids Clothes (Size 4-5)",
            body: """
            <p>Cleaning out closets! Free bag of kids clothes, mostly size 4-5.</p>
            <p>Mix of brands - Gap, H&M, Target. All gently used, some barely worn.</p>
            <p>About 20 items total - shirts, pants, a few dresses.</p>
            <p>First come first served. On my stoop at 4th St & 7th Ave starting 10am Saturday.</p>
            """,
            snippet: "Cleaning out closets! Free bag of kids clothes, mostly size 4-5...",
            senderName: "Amy Chen",
            hashtags: [
                Hashtag(name: "ForFree", colorHex: "#2196F3"),
                Hashtag(name: "Kids", colorHex: "#FF5722"),
                Hashtag(name: "SouthSlope", colorHex: "#E91E63")
            ],
            attachments: nil,
            price: nil
        ),
        Post(
            id: 6,
            topicId: 1006,
            created: Date().addingTimeInterval(-345600),
            subject: "FS: Uppababy Vista Stroller - 2023 Model",
            body: """
            <p>Selling our beloved Uppababy Vista stroller. 2023 model in Gregory (blue melange) color.</p>
            <p>Includes:</p>
            <ul>
                <li>Main stroller frame</li>
                <li>Bassinet + stand</li>
                <li>Toddler seat</li>
                <li>Rain cover</li>
                <li>Bug shield</li>
            </ul>
            <p>Excellent condition - always stored indoors. Original price was $1,100.</p>
            <p>Located in North Slope.</p>
            """,
            snippet: "Selling our beloved Uppababy Vista stroller. 2023 model in Gregory color...",
            senderName: "David Park",
            hashtags: [
                Hashtag(name: "ForSale", colorHex: "#4CAF50"),
                Hashtag(name: "BabyGear", colorHex: "#00BCD4"),
                Hashtag(name: "NorthSlope", colorHex: "#9C27B0")
            ],
            attachments: [
                Attachment(url: "https://example.com/stroller1.jpg", thumbnailUrl: "https://example.com/stroller1_thumb.jpg"),
                Attachment(url: "https://example.com/stroller2.jpg", thumbnailUrl: "https://example.com/stroller2_thumb.jpg"),
                Attachment(url: "https://example.com/stroller3.jpg", thumbnailUrl: "https://example.com/stroller3_thumb.jpg")
            ],
            price: "$650"
        )
    ]
    
    static let postsResponse = PostsResponse(
        messages: posts,
        nextCursor: nil,
        hasMore: false
    )
}
