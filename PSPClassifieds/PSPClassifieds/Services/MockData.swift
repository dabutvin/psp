import Foundation

enum MockData {
    static let hashtags: [Hashtag] = [
        Hashtag(name: "ForSale", colorHex: "#4CAF50", count: 150),
        Hashtag(name: "ForFree", colorHex: "#2196F3", count: 45),
        Hashtag(name: "ISO", colorHex: "#FF9800", count: 75),
        Hashtag(name: "NorthSlope", colorHex: "#9C27B0", count: 60),
        Hashtag(name: "SouthSlope", colorHex: "#E91E63", count: 55),
        Hashtag(name: "BabyGear", colorHex: "#00BCD4", count: 90),
        Hashtag(name: "Toddler", colorHex: "#FFEB3B", count: 65),
        Hashtag(name: "Kids", colorHex: "#FF5722", count: 80)
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
                Hashtag(name: "ForSale", colorHex: "#4CAF50", count: nil),
                Hashtag(name: "NorthSlope", colorHex: "#9C27B0", count: nil),
                Hashtag(name: "Toddler", colorHex: "#FFEB3B", count: nil)
            ],
            attachments: [
                // Real PSP image URLs - requires authentication
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725407/0/IMG_0739.jpeg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725407/0?thumb=1",
                    filename: "IMG_0739.jpeg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 0
                ),
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725407/1/IMG_0740.jpeg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725407/1?thumb=1",
                    filename: "IMG_0740.jpeg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 1
                )
            ],
            price: "$40",
            isReply: false
        ),
        Post(
            id: 2,
            topicId: 117553742,
            created: Date().addingTimeInterval(-7200),
            subject: "FS: Snoo Bassinet, Swaddles and Sheets - $500",
            body: """
            <p>Snoo is in excellent condition! We're the second owners and everything works perfectly. Comes with:</p>
            <ul>
                <li>5 sheets</li>
                <li>11 swaddles that include sizes S, M, and L</li>
                <li>4 Coterie wipe packs (if you'd like them!)</li>
            </ul>
            <p>We're a pet free and smoke free household and everything has been washed.</p>
            <p>$500, pick up is in Prospect Heights.</p>
            <p>Thanks!<br/>Caroline, mom to James (4 months)</p>
            """,
            snippet: "Snoo is in excellent condition! We're the second owners and everything works perfectly...",
            senderName: "Caroline Appling",
            hashtags: [
                Hashtag(name: "ForSale", colorHex: "#8ec2ee", count: nil),
                Hashtag(name: "ProspectHeights", colorHex: "#93ad59", count: nil),
                Hashtag(name: "BabyGear", colorHex: "#8ec2ee", count: nil)
            ],
            attachments: [
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/0/IMG_1286.jpg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/0?thumb=1",
                    filename: "IMG_1286.jpg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 0
                ),
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/1/IMG_1296.jpg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/1?thumb=1",
                    filename: "IMG_1296.jpg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 1
                ),
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/2/IMG_1299.jpg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725415/2?thumb=1",
                    filename: "IMG_1299.jpg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 2
                )
            ],
            price: "$500",
            isReply: false
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
                Hashtag(name: "ISO", colorHex: "#FF9800", count: nil),
                Hashtag(name: "BabyGear", colorHex: "#00BCD4", count: nil)
            ],
            attachments: nil,
            price: nil,
            isReply: false
        ),
        Post(
            id: 4,
            topicId: 117553741,
            created: Date().addingTimeInterval(-172800),
            subject: "FS: 7AM Enfant Toddler Mittens",
            body: """
            <p>Hi PSP.</p>
            <p>Selling a pair of super cozy 7AM Enfant toddler Polar Mittens (just like the stroller Warmmuffs but in mitten form!) in great condition.</p>
            <p>Bordeaux color, soft fuzzy lining.</p>
            <p>Tag says XL but they look small - would likely fit 2-3 year olds.</p>
            <p>Asking $10.</p>
            <p>Pick up in North Slope.</p>
            <p>Claire (mom to N & J)</p>
            """,
            snippet: "Selling a pair of super cozy 7AM Enfant toddler Polar Mittens...",
            senderName: "Claire Bourgeois",
            hashtags: [
                Hashtag(name: "ForSale", colorHex: "#8ec2ee", count: nil),
                Hashtag(name: "Toddler", colorHex: "#89bfbd", count: nil),
                Hashtag(name: "NorthSlope", colorHex: "#93ad59", count: nil)
            ],
            attachments: [
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725414/0/image0.jpeg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725414/0?thumb=1",
                    filename: "image0.jpeg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 0
                )
            ],
            price: "$10",
            isReply: false
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
                Hashtag(name: "ForFree", colorHex: "#2196F3", count: nil),
                Hashtag(name: "Kids", colorHex: "#FF5722", count: nil),
                Hashtag(name: "SouthSlope", colorHex: "#E91E63", count: nil)
            ],
            attachments: nil,
            price: nil,
            isReply: false
        ),
        Post(
            id: 6,
            topicId: 117553733,
            created: Date().addingTimeInterval(-345600),
            subject: "FS: Large bundle of Magnatiles",
            body: """
            <p>FS: Large bundle of Magnatiles</p>
            <p>We are ready to part with our beloved (and large!) collection of Magnatiles.</p>
            <p>The bundle includes the following:</p>
            <ul>
                <li>26 big squares</li>
                <li>76 small squares</li>
                <li>31 small triangles</li>
                <li>25 tall triangles</li>
                <li>15 medium triangles</li>
                <li>4 rectangles</li>
                <li>4 animals (jungle)</li>
                <li>6 windows</li>
                <li>3 staircases</li>
                <li>2 truck chassis</li>
                <li>about 10 miscellaneous shapes</li>
            </ul>
            <p>Asking $100 for the bundle (will toss in a fabric IKEA bin to carry them all!)</p>
            <p>Pick-up center slope this weekend</p>
            <p>Maren (mom of 2)</p>
            """,
            snippet: "We are ready to part with our beloved (and large!) collection of Magnatiles...",
            senderName: "Maren Ullrich",
            hashtags: [
                Hashtag(name: "ForSale", colorHex: "#8ec2ee", count: nil),
                Hashtag(name: "CenterSlope", colorHex: "#4191d6", count: nil),
                Hashtag(name: "Kids", colorHex: "#FF5722", count: nil)
            ],
            attachments: [
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725409/0/IMG_4259.jpeg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725409/0?thumb=1",
                    filename: "IMG_4259.jpeg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 0
                ),
                Attachment(
                    downloadUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725409/1/IMG_4263.jpeg",
                    thumbnailUrl: "https://groups.parkslopeparents.com/g/Classifieds/attachment/725409/1?thumb=1",
                    filename: "IMG_4263.jpeg",
                    mediaType: "image/jpeg",
                    attachmentIndex: 1
                )
            ],
            price: "$100",
            isReply: false
        )
    ]
    
    static let postsResponse = PostsResponse(
        messages: posts,
        nextCursor: nil,
        hasMore: false
    )
}
