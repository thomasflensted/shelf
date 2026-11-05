import Foundation
import Testing
@testable import Shelf

struct ImporterTests {
    @Test func missingFormatsSkipsExtensionsTheBookHas() {
        let book = makeBook(files: ["Title.epub"])
        let files = ["/x/a.EPUB", "/x/a.mobi"].map { URL(fileURLWithPath: $0) }
        #expect(Importer.missingFormats(files, in: book).map(\.lastPathComponent) == ["a.mobi"])
    }

    @Test func folderNameUsesFirstAuthorAndSafeTitle() {
        let book = makeBook(title: "Good Omens: The Nice and Accurate", author: "Terry Pratchett & Neil Gaiman")
        #expect(Importer.folderName(for: book) == "Terry Pratchett/Good Omens_ The Nice and Accurate")
    }

    @Test func summaryMentionsOnlyWhatHappened() {
        #expect(Importer.Result(added: 1).summary == "Added 1 book")
        #expect(Importer.Result(added: 2, merged: 1, skipped: 3).summary == "Added 2 books, 1 new format, 3 already in library")
    }

    @Test func importsOnceAndSkipsDuplicatesAfterwards() throws {
        let source = try TemporaryDirectory()
        let library = try TemporaryDirectory()
        try Data("hello".utf8).write(to: source.url.appendingPathComponent("Some Book.txt"))

        let first = Importer.run(urls: [source.url], root: library.url, existing: []) { _, _ in }
        let second = Importer.run(urls: [source.url], root: library.url, existing: first.books) { _, _ in }

        #expect(first.added == 1)
        let book = try #require(first.books.first)
        #expect(book.title == "Some Book")
        #expect(book.author == Book.unknownAuthor)
        #expect(FileManager.default.fileExists(atPath: book.folderURL(in: library.url).appendingPathComponent("Some Book.txt").path))
        #expect(second.added == 0 && second.skipped == 1)
    }

    @Test func calibreFolderBecomesOneBookWithAllFormats() throws {
        let source = try TemporaryDirectory()
        let folder = source.url.appendingPathComponent("Terry Pratchett/Mort (12)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let opf = "<package><metadata><title>Mort</title><creator>Terry Pratchett</creator></metadata></package>"
        try Data(opf.utf8).write(to: folder.appendingPathComponent("metadata.opf"))
        for ext in ["txt", "rtf"] { try Data().write(to: folder.appendingPathComponent("Mort.\(ext)")) }

        let candidates = Importer.collect([source.url])

        #expect(candidates.count == 1)
        #expect(candidates.first?.files.count == 2)
        #expect(candidates.first?.opf != nil)
    }
}

struct TemporaryDirectory {
    let url: URL

    init() throws {
        let tmp = realpath(FileManager.default.temporaryDirectory.path, nil)!
        defer { free(tmp) }
        url = URL(fileURLWithPath: String(cString: tmp)).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
