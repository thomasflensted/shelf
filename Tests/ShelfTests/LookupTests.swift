import Testing
@testable import Shelf

struct LookupTests {
    @Test func shortTitleDropsSubtitles() {
        #expect(BookLookup.shortTitle("Winners Take All: The Elite Charade") == "Winners Take All")
        #expect(BookLookup.shortTitle("Number Theory (Dover Books on Mathematics)") == "Number Theory")
        #expect(BookLookup.shortTitle("Origin") == "Origin")
    }

    @Test func cleanDescriptionRemovesOpenLibrarySourceNotes() {
        let raw = """
        A great book. ([source][1])

        ----------
        See also: Something
        [1]: https://example.com
        """
        #expect(OpenLibrary.cleanDescription(raw) == "A great book.")
        #expect(OpenLibrary.cleanDescription("[1]: https://example.com") == nil)
    }

    @Test func fillingTakesOnlyMissingDetails() {
        var openLibrary = BookInfo(source: "Open Library", title: "T")
        openLibrary.pages = 300
        var google = BookInfo(source: "Google Books", title: "T")
        google.pages = 280
        google.description = "From Google"
        google.subjects = ["History"]

        let merged = openLibrary.filling(from: google)

        #expect(merged.source == "Open Library")
        #expect(merged.pages == 300)
        #expect(merged.description == "From Google")
        #expect(merged.subjects == ["History"])
        #expect(openLibrary.isMissingDetails && !merged.isMissingDetails)
    }
}
