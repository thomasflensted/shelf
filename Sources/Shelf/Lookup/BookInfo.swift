import Foundation

struct BookInfo: Codable, Hashable {
    var source: String
    var title: String
    var year: String?
    var publisher: String?
    var pages: Int?
    var subjects: [String] = []
    var description: String?
    var rating: Double?
    var ratingsCount: Int?
    var isbn: String?
    var link: URL?

    var isMissingDetails: Bool { description == nil || pages == nil }

    func filling(from other: BookInfo) -> BookInfo {
        var info = self
        info.description = description ?? other.description
        info.pages = pages ?? other.pages
        info.publisher = publisher ?? other.publisher
        if subjects.isEmpty { info.subjects = other.subjects }
        return info
    }
}

enum LookupState: Equatable {
    case loading
    case found(BookInfo)
    case notFound
    case failed(String)
}
