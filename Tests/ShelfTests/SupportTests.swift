import Testing
@testable import Shelf

struct FormatsTests {
    @Test func bestPicksHighestRankedAvailableFormat() {
        #expect(Formats.best(of: ["a.epub", "a.mobi", "a.azw3"], in: Formats.kindleOrder) == "a.azw3")
        #expect(Formats.best(of: ["a.epub", "a.MOBI"], in: Formats.kindleOrder) == "a.MOBI")
        #expect(Formats.best(of: ["a.epub"], in: Formats.kindleOrder) == nil)
    }

    @Test func isBookChecksExtensionCaseInsensitively() {
        #expect(Formats.isBook("Book.AZW3"))
        #expect(!Formats.isBook("cover.jpg"))
    }
}

struct StringTests {
    @Test func safeFileNameReplacesPathCharactersAndHiddenPrefix() {
        #expect("AC/DC: Live?".safeFileName == "AC_DC_ Live_")
        #expect("..hidden".safeFileName == "hidden")
        #expect("  ".safeFileName == "Untitled")
        #expect(String(repeating: "x", count: 100).safeFileName.count == 80)
    }

    @Test func strippingHTMLCollapsesWhitespace() {
        #expect("<p>Hello&nbsp;<b>world</b></p>\n\n".strippingHTML == "Hello world")
    }

    @Test func countedPluralizes() {
        #expect(counted(1, "book") == "1 book")
        #expect(counted(0, "book") == "0 books")
        #expect(counted(3, "leftover folder") == "3 leftover folders")
    }
}

struct ViewLogicTests {
    @Test func sortOptionRoundTripsThroughComparators() {
        for option in SortOption.allCases {
            #expect(SortOption(option.comparators) == option)
        }
    }

    @Test func plainClickSelectsOnlyThatItem() {
        let result = GridSelection.click(3, in: [1, 2, 3, 4], selection: [1, 2], anchor: 1, command: false, shift: false)
        #expect(result.selection == [3])
        #expect(result.anchor == 3)
    }

    @Test func commandClickToggles() {
        let added = GridSelection.click(3, in: [1, 2, 3], selection: [1], anchor: 1, command: true, shift: false)
        #expect(added.selection == [1, 3])
        let removed = GridSelection.click(1, in: [1, 2, 3], selection: [1, 3], anchor: 3, command: true, shift: false)
        #expect(removed.selection == [3])
    }

    @Test func shiftClickSelectsRangeFromAnchorInEitherDirection() {
        #expect(GridSelection.click(4, in: [1, 2, 3, 4, 5], selection: [2], anchor: 2, command: false, shift: true).selection == [2, 3, 4])
        #expect(GridSelection.click(1, in: [1, 2, 3, 4, 5], selection: [3], anchor: 3, command: false, shift: true).selection == [1, 2, 3])
    }

    @Test func ratingStarsRoundToHalves() {
        #expect(RatingStars.symbols(for: 3.6) == ["star.fill", "star.fill", "star.fill", "star.leadinghalf.filled", "star"])
        #expect(RatingStars.symbols(for: 4.8) == Array(repeating: "star.fill", count: 5))
    }
}
