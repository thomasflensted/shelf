import Foundation

enum GoogleBooks {
    private struct Response: Decodable { let items: [Item]? }
    private struct Item: Decodable { let volumeInfo: Volume }

    private struct Volume: Decodable {
        let title: String?
        let publishedDate: String?
        let publisher: String?
        let pageCount: Int?
        let categories: [String]?
        let description: String?
        let averageRating: Double?
        let ratingsCount: Int?
        let infoLink: URL?
    }

    static func lookup(title: String, author: String, isbn: String?) async throws -> BookInfo? {
        let query = isbn.map { "isbn:\($0)" }
            ?? "intitle:\(BookLookup.shortTitle(title))" + (author.isEmpty ? "" : " inauthor:\(author)")
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "maxResults", value: "1")]
        let response: Response? = try await BookLookup.fetch(components.url!)
        guard let volume = response?.items?.first?.volumeInfo else { return nil }
        return BookInfo(
            source: "Google Books",
            title: volume.title ?? title,
            year: volume.publishedDate.map { String($0.prefix(4)) },
            publisher: volume.publisher,
            pages: volume.pageCount,
            subjects: volume.categories ?? [],
            description: volume.description?.strippingHTML,
            rating: volume.averageRating,
            ratingsCount: volume.ratingsCount,
            link: volume.infoLink)
    }
}
