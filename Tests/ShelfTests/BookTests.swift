import Foundation
import Testing
@testable import Shelf

func makeBook(title: String = "Title", author: String = "Ann Author", files: [String] = []) -> Book {
    Book(title: title, author: author, folder: "", files: files)
}

struct BookTests {
    @Test func authorSortPutsLastNameFirst() {
        #expect(makeBook(author: "Agatha Christie").authorSort == "Christie, Agatha")
        #expect(makeBook(author: "Joseph S. Nye Jr. & Someone Else").authorSort == "Jr., Joseph S. Nye")
        #expect(makeBook(author: "Plato").authorSort == "Plato")
    }

    @Test func seriesLabelShowsWholeAndFractionalNumbers() {
        var book = makeBook()
        #expect(book.seriesLabel == "")
        book.series = "Discworld"
        #expect(book.seriesLabel == "Discworld")
        book.seriesIndex = 3
        #expect(book.seriesLabel == "Discworld #3")
        book.seriesIndex = 2.5
        #expect(book.seriesLabel == "Discworld #2.5")
    }

    @Test func dedupeKeyIgnoresAuthorWordOrderAndPunctuation() {
        #expect(Book.dedupeKey(title: "The Body", author: "Bryson, Bill") == Book.dedupeKey(title: "The body!", author: "Bill Bryson"))
        #expect(Book.dedupeKey(title: "The Body", author: "Bill Bryson") != Book.dedupeKey(title: "At Home", author: "Bill Bryson"))
    }

    @Test func matchesRequiresEveryWordAnywhere() {
        var book = makeBook(title: "Guards! Guards!", author: "Terry Pratchett")
        book.tags = ["Fantasy"]
        #expect(book.matches("pratchett guards"))
        #expect(book.matches("FANTASY"))
        #expect(!book.matches("pratchett mort"))
    }

    @Test func preferredFilesFollowReadingOrder() {
        let book = makeBook(files: ["b.pdf", "b.mobi", "b.epub", "b.xyz"])
        #expect(book.preferredFiles == ["b.epub", "b.mobi", "b.pdf", "b.xyz"])
    }

    @Test func fillingGapsKeepsExistingValues() {
        var book = makeBook()
        book.summary = "Mine"
        var info = BookInfo(source: "Test", title: "Title")
        info.description = "Theirs"
        info.isbn = "9780000000000"
        info.subjects = ["a", "b", "c", "d", "e", "f"]

        let filled = book.fillingGaps(from: info)

        #expect(filled.summary == "Mine")
        #expect(filled.isbn == "9780000000000")
        #expect(filled.tags == ["a", "b", "c", "d", "e"])
    }
}
