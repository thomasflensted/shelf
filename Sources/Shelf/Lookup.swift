import Foundation
import Observation

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

/// Looks books up on Open Library (free, no key), topping up from Google Books when it answers.
@MainActor
@Observable
final class InfoStore {
    private(set) var states: [Book.ID: LookupState] = [:]
    private var cache: [String: BookInfo?] = [:]

    private static let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Shelf")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lookups.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let saved = try? JSONDecoder().decode([String: BookInfo?].self, from: data) {
            cache = saved
        }
    }

    private func key(_ book: Book) -> String { book.isbn ?? book.dedupeKey }

    func state(for book: Book) -> LookupState? {
        if let s = states[book.id] { return s }
        if let hit = cache[key(book)] { return hit.map(LookupState.found) ?? .notFound }
        return nil
    }

    func load(_ book: Book, isbnFromFiles: @escaping @Sendable () -> String?, force: Bool = false) {
        if !force, let s = state(for: book), s != .loading { states[book.id] = s; return }
        if states[book.id] == .loading { return }
        states[book.id] = .loading
        let k = key(book)
        Task {
            do {
                var isbn = book.isbn
                if isbn == nil { isbn = await Task.detached { isbnFromFiles() }.value }
                let info = try await Self.lookup(title: book.title, author: book.author, isbn: isbn)
                cache[k] = .some(info)
                states[book.id] = info.map(LookupState.found) ?? .notFound
                persist()
            } catch {
                states[book.id] = .failed(error.localizedDescription)
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }

    // MARK: Network

    nonisolated private static func json(_ url: URL) async throws -> [String: Any] {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue("Shelf/1.0 (personal ebook manager)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// "Winners Take All: The Elite Charade…" → "Winners Take All"
    nonisolated static func shortTitle(_ t: String) -> String {
        var s = t
        for sep in [":", " (", " - ", ";"] {
            if let r = s.range(of: sep) { s = String(s[..<r.lowerBound]) }
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    nonisolated static func lookup(title: String, author: String, isbn: String?) async throws -> BookInfo? {
        let firstAuthor = author.components(separatedBy: " & ").first ?? author
        var info = try await openLibrary(title: title, author: firstAuthor, isbn: isbn)
        // Google Books often has a better description; its keyless quota is unreliable, so failures are fine.
        if info == nil || info?.description == nil || info?.pages == nil,
           let g = try? await googleBooks(title: title, author: firstAuthor, isbn: isbn ?? info?.isbn) {
            if var i = info {
                i.description = i.description ?? g.description
                i.pages = i.pages ?? g.pages
                i.publisher = i.publisher ?? g.publisher
                if i.subjects.isEmpty { i.subjects = g.subjects }
                info = i
            } else {
                info = g
            }
        }
        return info
    }

    nonisolated private static func openLibrary(title: String, author: String, isbn: String?) async throws -> BookInfo? {
        let fields = "key,title,author_name,first_publish_year,number_of_pages_median,subject,publisher,ratings_average,ratings_count,isbn,cover_i"
        func search(_ items: [URLQueryItem]) async throws -> [String: Any]? {
            var c = URLComponents(string: "https://openlibrary.org/search.json")!
            c.queryItems = items + [.init(name: "limit", value: "1"), .init(name: "fields", value: fields)]
            return (try await json(c.url!)["docs"] as? [[String: Any]])?.first
        }

        var doc: [String: Any]?
        if let isbn { doc = try await search([.init(name: "isbn", value: isbn)]) }
        if doc == nil, !author.isEmpty, author != "Unknown" {
            doc = try await search([.init(name: "title", value: shortTitle(title)), .init(name: "author", value: author)])
        }
        if doc == nil { doc = try await search([.init(name: "title", value: shortTitle(title))]) }
        guard let doc, let key = doc["key"] as? String else { return nil }

        var info = BookInfo(source: "Open Library", title: doc["title"] as? String ?? title)
        info.authors = doc["author_name"] as? [String] ?? []
        info.year = (doc["first_publish_year"] as? Int).map(String.init)
        info.pages = doc["number_of_pages_median"] as? Int
        info.publisher = (doc["publisher"] as? [String])?.first
        info.subjects = Array((doc["subject"] as? [String] ?? []).filter { !$0.contains(":") && $0.count < 40 }.prefix(10))
        info.rating = doc["ratings_average"] as? Double
        info.ratingsCount = doc["ratings_count"] as? Int
        info.isbn = isbn ?? (doc["isbn"] as? [String])?.first { $0.count == 13 }
        info.link = URL(string: "https://openlibrary.org\(key)")
        if let cover = doc["cover_i"] as? Int { info.coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(cover)-L.jpg") }

        let work = try? await json(URL(string: "https://openlibrary.org\(key).json")!)
        if let d = work?["description"] as? String {
            info.description = d
        } else if let d = (work?["description"] as? [String: Any])?["value"] as? String {
            info.description = d
        }
        // Strip Open Library's markdown-ish source links: "([source][1])", "----------", "[1]: http…"
        info.description = info.description.map { d in
            d.components(separatedBy: "\n")
                .filter { !$0.hasPrefix("[") && !$0.hasPrefix("---") && !$0.lowercased().hasPrefix("see also") }
                .joined(separator: "\n")
                .replacingOccurrences(of: "\\(\\[[^\\]]*\\]\\[\\d+\\]\\)", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.flatMap { $0.isEmpty ? nil : $0 }
        return info
    }

    nonisolated private static func googleBooks(title: String, author: String, isbn: String?) async throws -> BookInfo? {
        let q = isbn.map { "isbn:\($0)" } ?? "intitle:\(shortTitle(title))" + (author.isEmpty ? "" : " inauthor:\(author)")
        var c = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        c.queryItems = [.init(name: "q", value: q), .init(name: "maxResults", value: "1")]
        guard let item = (try await json(c.url!)["items"] as? [[String: Any]])?.first,
              let v = item["volumeInfo"] as? [String: Any] else { return nil }
        var info = BookInfo(source: "Google Books", title: v["title"] as? String ?? title)
        info.authors = v["authors"] as? [String] ?? []
        info.year = (v["publishedDate"] as? String).map { String($0.prefix(4)) }
        info.publisher = v["publisher"] as? String
        info.pages = v["pageCount"] as? Int
        info.subjects = v["categories"] as? [String] ?? []
        info.description = (v["description"] as? String).map {
            $0.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        info.rating = v["averageRating"] as? Double
        info.ratingsCount = v["ratingsCount"] as? Int
        info.link = (v["infoLink"] as? String).flatMap(URL.init(string:))
        return info
    }
}
