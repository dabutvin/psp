import XCTest
@testable import PSPClassifieds

final class HTMLTextViewTests: XCTestCase {

    // MARK: - Basic HTML

    func testSimpleParagraph() {
        let html = "<p>Hello world</p>"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertEqual(text, "Hello world")
    }

    func testLineBreaks() {
        let html = "Line one<br/>Line two<br>Line three"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertEqual(text, "Line one\nLine two\nLine three")
    }

    func testMultipleParagraphs() {
        let html = "<p>First paragraph</p><p>Second paragraph</p>"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertEqual(text, "First paragraph\n\nSecond paragraph")
    }

    func testDivElements() {
        let html = "<div>Block one</div><div>Block two</div>"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertEqual(text, "Block one\nBlock two")
    }

    func testListItems() {
        let html = "<ul><li>Item one</li><li>Item two</li></ul>"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertTrue(text.contains("• Item one"))
        XCTAssertTrue(text.contains("• Item two"))
    }

    func testHTMLEntityDecoding() {
        let html = "<div>Books &amp; Toys &lt;3</div>"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertEqual(text, "Books & Toys <3")
    }

    func testImgTagsStripped() {
        let html = """
        <div>Check out this photo:</div>
        <img src="https://example.com/photo.jpg" width="300"/>
        <div>Pretty cool right?</div>
        """
        let text = HTMLTextView.plainText(from: html)
        XCTAssertFalse(text.contains("img"))
        XCTAssertFalse(text.contains("example.com"))
        XCTAssertTrue(text.contains("Check out this photo:"))
        XCTAssertTrue(text.contains("Pretty cool right?"))
    }

    // MARK: - Whitespace Collapsing

    func testCollapsesExcessiveTabs() {
        let text = HTMLTextView.collapseWhitespace("Hello\t\t\t\tWorld")
        XCTAssertEqual(text, "Hello World")
    }

    func testCollapsesExcessiveNewlines() {
        let text = HTMLTextView.collapseWhitespace("Line one\n\n\n\n\nLine two")
        XCTAssertEqual(text, "Line one\n\nLine two")
    }

    func testTrimsWhitespacePerLine() {
        let text = HTMLTextView.collapseWhitespace("  Hello  \n  World  ")
        XCTAssertEqual(text, "Hello\nWorld")
    }

    func testTrimsNonBreakingSpaces() {
        let text = HTMLTextView.collapseWhitespace("\u{00A0}Hello\u{00A0}")
        XCTAssertEqual(text, "Hello")
    }

    func testCollapsesWhitespaceOnlyLines() {
        let text = HTMLTextView.collapseWhitespace("Hello\n  \t  \n  \t  \n  \t  \nWorld")
        XCTAssertEqual(text, "Hello\n\nWorld")
    }

    // MARK: - Table-heavy Event HTML (the Real Estate post bug)

    func testEventPostWithNestedTables() {
        let html = """
        <table width="100%">
        <tbody><tr>
        <td>
        <table width="100%">
        <tbody><tr>
        <td>
        <table width="100%">
        <tbody><tr>
        <td>
        <table width="100%">
        <tbody><tr>
        <td width="70" valign="top">
        <table>
        <tbody><tr>
        <td>
        Mar
        </td>
        </tr>
        <tr>
        <td>
        <div style="line-height: 1; margin: 0">4</div>
        <div style="line-height: 1; margin: 0; margin-top: 2px">Wed</div>
        </td>
        </tr>
        </tbody></table>
        </td>
        <td valign="top">
        <span style="height: 13px; width: 13px; border-radius: 50%; display: inline-block; vertical-align: middle"></span>
        Real Estate Post Requirements and Guidelines
        </td>
        </tr>
        </tbody></table>
        </td>
        </tr>
        </tbody></table>
        <table width="100%">
        <tbody><tr>
        <td>
        Date and Time
        <p style="margin: 0 0 15px 0; line-height: 1.5">
        Wednesday, March 4, 2026
        (UTC-05:00) America/New York
        </p>
        </td>
        </tr>
        </tbody></table>
        <table width="100%">
        <tbody><tr>
        <td>
        <a href="https://groups.parkslopeparents.com/g/Classifieds/viewevent?eventid=3028096" style="display: inline-block; padding: 10px 20px; text-decoration: none; border-radius: 4px" rel="nofollow">
        View Event &#x2192;
        </a>
        </td>
        </tr>
        </tbody></table>
        <table width="100%">
        <tbody><tr>
        <td>
        Description
        <div style="line-height: 1.6">
        <div><strong>REAL ESTATE POST REQUIREMENTS AND GUIDELINES</strong></div>
        <div>&nbsp;</div>
        <div>Want to post a Real Estate message on the Park Slope Parents classifieds?&nbsp; Great!</div>
        <div style="padding-left: 30px"><br/>NOTE: Real Estate posts are screened by special moderators so there may be a 24-36 hour delay in posting.</div>
        <div><br/><strong>POLICY:<br/><br/></strong></div>
        <div><strong>***POSTING ISO SUBLETS/RENTAL/SALE PROPERTIES***</strong></div>
        <div>Members can post ISO real estate for themselves AND can also post on behalf of family/friends.</div>
        </div>
        </td>
        </tr>
        </tbody></table>
        <table width="100%">
        <tbody><tr>
        <td>
        <a href="https://groups.parkslopeparents.com/g/Classifieds/ics/invite.ics?eventid=3028096" style="text-decoration: none" rel="nofollow">
        <strong>Add to Calendar</strong>
        </a>
        <span style="margin: 0 10px">|</span>
        <a href="https://groups.parkslopeparents.com/g/Classifieds/viewevent?eventid=3028096" style="text-decoration: none" rel="nofollow">
        View Full Details
        </a>
        </td>
        </tr>
        </tbody></table>
        </td>
        </tr>
        </tbody></table>
        """

        let text = HTMLTextView.plainText(from: html)

        // The body should NOT be blank
        XCTAssertFalse(text.isEmpty, "Event post body should not be empty")

        // Key content from the event description must be present
        XCTAssertTrue(text.contains("REAL ESTATE POST REQUIREMENTS AND GUIDELINES"),
                       "Should contain the event title")
        XCTAssertTrue(text.contains("Want to post a Real Estate message"),
                       "Should contain the description text")
        XCTAssertTrue(text.contains("POLICY"),
                       "Should contain policy section")
        XCTAssertTrue(text.contains("POSTING ISO SUBLETS"),
                       "Should contain the sublets section")
        XCTAssertTrue(text.contains("Date and Time"),
                       "Should contain date/time header")
        XCTAssertTrue(text.contains("Wednesday, March 4, 2026"),
                       "Should contain the event date")

        // Calendar date from the nested table headers
        XCTAssertTrue(text.contains("Mar"),
                       "Should contain month abbreviation from calendar widget")

        // Should not have excessive whitespace (the original bug)
        XCTAssertFalse(text.contains("\t\t\t"), "Should not contain runs of tabs")
        XCTAssertFalse(text.contains("   "), "Should not contain runs of spaces")
    }

    // MARK: - preprocessHTML preserves <a> tags

    func testPreprocessHTMLPreservesLinks() {
        let html = """
        <div>Click <a href="https://example.com">here</a> for info.</div>
        """
        let processed = HTMLTextView.preprocessHTML(html)
        XCTAssertTrue(processed.contains("<a href=\"https://example.com\">here</a>"))
        XCTAssertFalse(processed.contains("<div>"))
    }

    func testPreprocessHTMLStripsNonLinkTags() {
        let html = "<table><tr><td><strong>Bold</strong> text</td></tr></table>"
        let processed = HTMLTextView.preprocessHTML(html)
        XCTAssertFalse(processed.contains("<table>"))
        XCTAssertFalse(processed.contains("<strong>"))
        XCTAssertTrue(processed.contains("Bold"))
        XCTAssertTrue(processed.contains("text"))
    }

    // MARK: - Typical classified post (regression test)

    func testTypicalClassifiedPost() {
        let html = """
        <div>
        <div>Snoo is in excellent condition! We&#39;re the second owners and everything works perfectly. Comes with:</div>
        <div><ul><li>5 sheets</li><li>11 swaddles</li><li>4 Coterie wipe packs</li></ul></div>
        <div>$500, pick up is in Prospect Heights.</div>
        <div><br/></div>
        <div>Thanks!</div>
        <div>Caroline, mom to James (4 months)</div>
        </div>
        """
        let text = HTMLTextView.plainText(from: html)

        XCTAssertTrue(text.contains("Snoo is in excellent condition"))
        XCTAssertTrue(text.contains("• 5 sheets"))
        XCTAssertTrue(text.contains("$500, pick up is in Prospect Heights"))
        XCTAssertTrue(text.contains("Caroline, mom to James (4 months)"))
    }

    func testPlainTextPost() {
        let html = "Simple plain text with no HTML tags at all."
        let text = HTMLTextView.plainText(from: html)
        XCTAssertEqual(text, "Simple plain text with no HTML tags at all.")
    }

    func testBlockquoteHandled() {
        let html = "<blockquote>Selling these barely worn pants.<br/>Pick up 7th &amp; President</blockquote>Anna (mom to v)"
        let text = HTMLTextView.plainText(from: html)
        XCTAssertTrue(text.contains("Selling these barely worn pants"))
        XCTAssertTrue(text.contains("Pick up 7th & President"))
        XCTAssertTrue(text.contains("Anna (mom to v)"))
    }
}
