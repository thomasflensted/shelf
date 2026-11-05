import Foundation
import Testing
@testable import Shelf

struct KindleFilesTests {
    @Test func asinIsReadFromAmazonFileNames() {
        #expect(KindleFiles.asin("Hillbilly Elegy_ A Memoir_B079L5DDB4") == "B079L5DDB4")
        #expect(KindleFiles.asin("Empire of AI_B0DW49YMRL_sample") == "B0DW49YMRL")
        #expect(KindleFiles.asin("My Clippings") == nil)
        #expect(KindleFiles.asin("Title_ABCDEFGHIJ") == nil)
    }

    @Test func prettyTitleRestoresPunctuationAndArticles() {
        #expect(KindleFiles.prettyTitle("Pragmatic Programmer, The_ Your journey to mastery_B07VRS84D1") == "The Pragmatic Programmer: Your journey to mastery")
        #expect(KindleFiles.prettyTitle("Go Programming Language, The (Addison-Wesley)_B0184N7WWS") == "The Go Programming Language (Addison-Wesley)")
        #expect(KindleFiles.prettyTitle("Empire of AI_B0DW49YMRL_sample") == "Empire of AI (sample)")
    }

    @Test func shortNamedSidecarBelongsToFullNamedBook() {
        let book = "The Sympathizer_ A Novel_B00PSSG4MM"
        #expect(KindleFiles.sidecar(book, belongsTo: book))
        #expect(KindleFiles.sidecar("The Sympathizer_B00PSSG4MM", belongsTo: book))
        #expect(!KindleFiles.sidecar("The Iliad_B07VN4J15X", belongsTo: book))
        #expect(!KindleFiles.sidecar("Other", belongsTo: "Mine"))
    }

    @Test func sidecarIsOrphanOnlyWithoutNameOrASINMatch() {
        #expect(!KindleFiles.isOrphan("Book", bookStems: ["Book"], asins: []))
        #expect(!KindleFiles.isOrphan("Short_B00PSSG4MM", bookStems: ["Long Name_B00PSSG4MM"], asins: ["B00PSSG4MM"]))
        #expect(KindleFiles.isOrphan("The Lean Startup_B005PR422K_sample", bookStems: ["Other"], asins: ["B00PSSG4MM"]))
    }

    @Test func purchasesAreAmazonFilesUnderDownloads() {
        let docs = URL(fileURLWithPath: "/Volumes/Kindle/documents")
        #expect(KindleFiles.isPurchase(docs.appendingPathComponent("Downloads/Items01/Title_B079L5DDB4.kfx"), documents: docs))
        #expect(!KindleFiles.isPurchase(docs.appendingPathComponent("Downloads/Items01/Title.mobi"), documents: docs))
        #expect(!KindleFiles.isPurchase(docs.appendingPathComponent("Title_B079L5DDB4.azw3"), documents: docs))
    }
}

struct KindleScannerTests {
    @Test func findsBooksSidecarsAndOrphans() throws {
        let docs = try TemporaryDirectory().url
        let items = docs.appendingPathComponent("Downloads/Items01")
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        for dir in ["Title_ Subtitle_B079L5DDB4.sdr", "Title_B079L5DDB4.sdr", "Gone_B005PR422K_sample.sdr"] {
            try FileManager.default.createDirectory(at: items.appendingPathComponent(dir), withIntermediateDirectories: true)
        }
        try Data(count: 10).write(to: items.appendingPathComponent("Title_ Subtitle_B079L5DDB4.kfx"))
        try Data(count: 5).write(to: docs.appendingPathComponent("Sideloaded - Someone.txt"))

        let result = KindleScanner.scan(docs)

        let purchase = try #require(result.items.first { $0.isPurchase })
        #expect(purchase.title == "Title: Subtitle")
        #expect(purchase.sidecars.count == 2)
        #expect(result.items.count == 2)
        #expect(result.orphans.map(\.lastPathComponent) == ["Gone_B005PR422K_sample.sdr"])
    }
}

struct KindleRulesTests {
    func item(_ name: String, isPurchase: Bool = false) -> KindleItem {
        KindleItem(url: URL(fileURLWithPath: "/k/\(name)"), title: "T", author: "A", size: 0, modified: .now,
                   sidecars: [], dedupeKey: "", isPurchase: isPurchase)
    }

    @Test func onlySideloadedBooksMissingFromLibraryNeedBackup() {
        #expect(item("a.mobi").needsBackup(isInLibrary: false))
        #expect(!item("a.mobi").needsBackup(isInLibrary: true))
        #expect(!item("a.kfx", isPurchase: true).needsBackup(isInLibrary: false))
        #expect(!item("My Clippings.txt").needsBackup(isInLibrary: false))
    }

    @Test func matchKeysRecogniseBooksSentByShelf() {
        let book = makeBook(title: "Mort", author: "Terry Pratchett")
        let sent = KindleItem(url: URL(fileURLWithPath: "/k/Mort - Terry Pratchett.azw3"), title: "Mort (Discworld 4)",
                              author: "", size: 0, modified: .now, sidecars: [], dedupeKey: "other", isPurchase: false)
        #expect(MatchKeys(items: [sent]).contains(book))
        #expect(MatchKeys(books: [book]).contains(sent))
        #expect(!MatchKeys(items: [sent]).contains(makeBook(title: "Sourcery", author: "Terry Pratchett")))
    }

    @Test func storageLevelThresholds() {
        #expect(StorageLevel(used: 50, total: 100) == .normal)
        #expect(StorageLevel(used: 80, total: 100) == .high)
        #expect(StorageLevel(used: 95, total: 100) == .almostFull)
        #expect(StorageLevel(used: 0, total: 0) == .normal)
    }
}
