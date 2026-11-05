import Foundation

/// Information about a book from an online catalogue.
struct BookInfo: Codable, Hashable {
    var source: String
    var title: String
    var authors: [String] = []
    var year: String?
    var publisher: String?
    var pages: Int?
    var subjects: [String] = []
    var description: String?
    var rating: Double?
    var ratingsCount: Int?
    var isbn: String?
    var link: URL?
    var coverURL: URL?
}

enum LookupState: Equatable {
    case loading
    case found(BookInfo)
    case notFound
    case failed(String)
}
