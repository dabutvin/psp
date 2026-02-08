import XCTest
@testable import PSPClassifieds

final class SimilarSearchQueryTests: XCTestCase {

    // MARK: - Prefix Removal
    
    func testRemovesFSPrefix() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Baby Stroller"), "Baby Stroller")
    }
    
    func testRemovesISOPrefix() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "ISO: Double Stroller"), "Double Stroller")
    }
    
    func testRemovesFREEPrefix() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FREE: Old Bookshelf"), "Old Bookshelf")
    }
    
    func testRemovesFFPrefix() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FF: Wooden baby blocks"), "Wooden baby blocks")
    }
    
    func testRemovesForSaleWithSpace() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "For sale: fleece pajamas"), "fleece pajamas")
    }
    
    // MARK: - Price Removal
    
    func testRemovesPrice() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Crib $200"), "Crib")
    }
    
    func testRemovesPriceWithCommas() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Dining Table $1,500"), "Dining Table")
    }
    
    func testRemovesPriceWithCents() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Toy $19.99"), "Toy")
    }
    
    // MARK: - Parenthetical Noise
    
    func testRemovesRepost() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "(Repost) FS: Lands End Fleece Robe 2T"), "Lands End Fleece Robe")
    }
    
    func testRemovesPriceDrop() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "(Price Drop) FS: Stroller $100"), "Stroller")
    }
    
    func testRemovesSold() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "(SOLD) FS: Baby Carrier"), "Baby Carrier")
    }
    
    func testRemovesSizeParenthetical() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Hannah Andersson Down Puffer (Sz 8)"), "Hannah Andersson Down Puffer")
    }
    
    // MARK: - Size Indicators
    
    func testRemovesSizeIndicators() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Kids Clothes 3T"), "Kids Clothes")
    }
    
    func testRemovesMonthSizes() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Baby Onesies 12M"), "Baby Onesies")
    }
    
    // MARK: - Separators
    
    func testRemovesPlusSeparators() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Stroller + Bassinet + Accessories"), "Stroller Bassinet Accessories")
    }
    
    func testRemovesSlashSeparators() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Books / Toys / Games"), "Books Toys Games")
    }
    
    func testRemovesCommas() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Ikea bedframe, full size"), "Ikea bedframe full size")
    }
    
    func testPreservesHyphensInWords() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: k-nex building toy"), "k-nex building toy")
    }
    
    func testRemovesStandaloneNumbers() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: 500 piece puzzle"), "puzzle")
    }
    
    func testRemovesNumberWords() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "Six toy dinosaurs"), "toy dinosaurs")
    }
    
    func testRemovesPieceAndSet() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: k-nex 705 piece set"), "k-nex")
    }
    
    func testRemovesDashSeparators() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Stroller - great deal"), "Stroller")
    }
    
    // MARK: - Filler Words
    
    func testRemovesFillerWords() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Fully loaded Uppababy Vista"), "Uppababy Vista")
    }
    
    func testRemovesConditionWords() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Excellent condition Baby Bjorn"), "Baby Bjorn")
    }
    
    func testRemovesMultipleFillerWords() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: Brand new never used Crib"), "Crib")
    }
    
    // MARK: - Hashtags
    
    func testRemovesHashtags() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "#ForSale Baby Monitor"), "Baby Monitor")
    }
    
    func testRemovesMultipleHashtags() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "#ForSale #BabyGear Stroller"), "Stroller")
    }
    
    // MARK: - Complex Examples
    
    func testComplexExample() {
        XCTAssertEqual(
            extractSimilarSearchQuery(from: "FS: Fully loaded Uppababy Vista rumble seat + bassinet + spare fabrics + more $250"),
            "Uppababy Vista rumble seat bassinet fabrics"
        )
    }
    
    func testAnotherComplexExample() {
        XCTAssertEqual(
            extractSimilarSearchQuery(from: "(Repost) FS: Like new Bugaboo Fox 3 complete set + extras - $800 OBO"),
            "Bugaboo Fox complete extras"
        )
    }
    
    // MARK: - Edge Cases
    
    func testReturnsNilForTooShort() {
        XCTAssertNil(extractSimilarSearchQuery(from: "FS: $50"))
    }
    
    func testReturnsNilForNilSubject() {
        XCTAssertNil(extractSimilarSearchQuery(from: nil))
    }
    
    func testReturnsNilForOnlyFillerWords() {
        XCTAssertNil(extractSimilarSearchQuery(from: "FS: Great condition $100"))
    }
    
    func testPreservesProductNames() {
        XCTAssertEqual(extractSimilarSearchQuery(from: "FS: 4moms MamaRoo"), "4moms MamaRoo")
    }
    
    // MARK: - Search Query Fallback
    
    func testGenerateSearchQueriesFourWords() {
        let queries = generateSearchQueries(from: "Industrial Steel Plant Stands")
        XCTAssertEqual(queries, [
            "Industrial Steel Plant Stands",
            "Industrial Steel",
            "Plant Stands"
        ])
    }
    
    func testGenerateSearchQueriesThreeWords() {
        let queries = generateSearchQueries(from: "Baby Car Seat")
        XCTAssertEqual(queries, [
            "Baby Car Seat",
            "Baby",
            "Car Seat"
        ])
    }
    
    func testGenerateSearchQueriesTwoWords() {
        let queries = generateSearchQueries(from: "Baby Stroller")
        XCTAssertEqual(queries, ["Baby Stroller"])
    }
    
    func testGenerateSearchQueriesOneWord() {
        let queries = generateSearchQueries(from: "Stroller")
        XCTAssertEqual(queries, ["Stroller"])
    }
    
    func testGenerateSearchQueriesFiveWords() {
        let queries = generateSearchQueries(from: "Wooden Baby Blocks For Photos")
        XCTAssertEqual(queries, [
            "Wooden Baby Blocks For Photos",
            "Wooden Baby",
            "Blocks For Photos",
            "Blocks",
            "For Photos"
        ])
    }
    
    func testGenerateSearchQueriesEmpty() {
        let queries = generateSearchQueries(from: "")
        XCTAssertEqual(queries, [])
    }
    
    func testGenerateSearchQueriesLongQuery() {
        let queries = generateSearchQueries(from: "MODERN DESIGNER WHITEWASHED MAPLE CAPSULE BENCH GORGEOUS")
        XCTAssertEqual(queries, [
            "MODERN DESIGNER WHITEWASHED MAPLE CAPSULE BENCH GORGEOUS",
            "MODERN DESIGNER WHITEWASHED",
            "MAPLE CAPSULE BENCH GORGEOUS",
            "MODERN",
            "DESIGNER WHITEWASHED",
            "MAPLE CAPSULE"
        ])
    }
}
