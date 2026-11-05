import Foundation

struct Book: Codable, Identifiable, Hashable {
    static let unknownAuthor = "Unknown"
    static let coverFileName = "cover.jpg"

    var id = UUID()
    var title: String
    var author: String
    var series: String?
    var seriesIndex: Double?
    var tags: [String] = []
    var summary: String?
    var isbn: String?
    var added = Date()
    var folder: String
    var files: [String]
    var hasCover = false
    var coverVersion = 0

    var coverKey: String { "\(id)-\(coverVersion)-\(hasCover)" }

    var formats: String { files.map { Formats.ext($0).uppercased() }.sorted().joined(separator: ", ") }

    var preferredFiles: [String] { Formats.sorted(files, by: Formats.readingOrder) }

    var firstAuthor: String { author.components(separatedBy: " & ").first ?? author }

    var authorSort: String {
        let parts = firstAuthor.split(separator: " ")
        guard parts.count > 1, let last = parts.last else { return firstAuthor }
        return "\(last), \(parts.dropLast().joined(separator: " "))"
    }

    var seriesNumber: String? {
        seriesIndex.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) }
    }

    var seriesLabel: String {
        guard let series, !series.isEmpty else { return "" }
        return seriesNumber.map { "\(series) #\($0)" } ?? series
    }

    var seriesSort: String { series.map { "\($0) \(String(format: "%08.2f", seriesIndex ?? 0))" } ?? "" }

    var dedupeKey: String { Book.dedupeKey(title: title, author: author) }

    static func dedupeKey(title: String, author: String) -> String {
        let titleKey = title.lowercased().filter { $0.isLetter || $0.isNumber }
        let wordOrderInsensitiveAuthorKey = author.lowercased().split { !($0.isLetter || $0.isNumber) }.sorted().joined()
        return titleKey + "|" + wordOrderInsensitiveAuthorKey
    }

    func matches(_ query: String) -> Bool {
        [title, author, series ?? "", tags.joined(separator: " ")].joined(separator: " ").containsAllWords(of: query)
    }

    func folderURL(in root: URL) -> URL { root.appendingPathComponent(folder, isDirectory: true) }

    func coverURL(in root: URL) -> URL { folderURL(in: root).appendingPathComponent(Book.coverFileName) }

    func fillingGaps(from info: BookInfo) -> Book {
        var book = self
        if book.summary == nil { book.summary = info.description }
        if book.isbn == nil { book.isbn = info.isbn }
        if book.tags.isEmpty { book.tags = Array(info.subjects.prefix(5)) }
        return book
    }
}
