import Foundation

enum OpenLibrary {
    private struct SearchResponse: Decodable { let docs: [Doc] }

    private struct Doc: Decodable {
        let key: String
        let title: String?
        let firstPublishYear: Int?
        let numberOfPagesMedian: Int?
        let subject: [String]?
        let publisher: [String]?
        let ratingsAverage: Double?
        let ratingsCount: Int?
        let isbn: [String]?
    }

    private struct Work: Decodable {
        let description: Description?

        struct Description: Decodable {
            let text: String

            init(from decoder: Decoder) throws {
                if let plain = try? decoder.singleValueContainer().decode(String.self) {
                    text = plain
                } else {
                    text = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .value)
                }
            }

            private enum Keys: CodingKey { case value }
        }
    }

    private static let fields = "key,title,first_publish_year,number_of_pages_median,subject,publisher,ratings_average,ratings_count,isbn"

    static func lookup(title: String, author: String, isbn: String?) async throws -> BookInfo? {
        let short = BookLookup.shortTitle(title)
        var doc: Doc?
        if let isbn { doc = try await search(["isbn": isbn]) }
        if doc == nil, !author.isEmpty, author != Book.unknownAuthor { doc = try await search(["title": short, "author": author]) }
        if doc == nil { doc = try await search(["title": short]) }
        guard let doc else { return nil }

        let work: Work? = try? await BookLookup.fetch(URL(string: "https://openlibrary.org\(doc.key).json")!)
        return BookInfo(
            source: "Open Library",
            title: doc.title ?? title,
            year: doc.firstPublishYear.map(String.init),
            publisher: doc.publisher?.first,
            pages: doc.numberOfPagesMedian,
            subjects: Array((doc.subject ?? []).filter { !$0.contains(":") && $0.count < 40 }.prefix(10)),
            description: work?.description.flatMap { cleanDescription($0.text) },
            rating: doc.ratingsAverage,
            ratingsCount: doc.ratingsCount,
            isbn: isbn ?? doc.isbn?.first { $0.count == 13 },
            link: URL(string: "https://openlibrary.org\(doc.key)"))
    }

    static func cleanDescription(_ text: String) -> String? {
        text.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("[") && !$0.hasPrefix("---") && !$0.lowercased().hasPrefix("see also") }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\\(\\[[^\\]]*\\]\\[\\d+\\]\\)", with: "", options: .regularExpression)
            .trimmed
            .nonEmpty
    }

    private static func search(_ query: [String: String]) async throws -> Doc? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            + [URLQueryItem(name: "limit", value: "1"), URLQueryItem(name: "fields", value: fields)]
        let response: SearchResponse? = try await BookLookup.fetch(components.url!)
        return response?.docs.first
    }
}
