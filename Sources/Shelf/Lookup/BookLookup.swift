import Foundation

enum BookLookup {
    static func lookup(title: String, author: String, isbn: String?) async throws -> BookInfo? {
        let openLibrary = try await OpenLibrary.lookup(title: title, author: author, isbn: isbn)
        guard openLibrary?.isMissingDetails ?? true else { return openLibrary }
        // Google Books' keyless quota is shared and often exhausted, so it only tops up and its failures are ignored.
        guard let google = try? await GoogleBooks.lookup(title: title, author: author, isbn: isbn ?? openLibrary?.isbn)
        else { return openLibrary }
        return openLibrary?.filling(from: google) ?? google
    }

    static func shortTitle(_ title: String) -> String {
        var short = title
        for separator in [":", " (", " - ", ";"] {
            if let range = short.range(of: separator) { short = String(short[..<range.lowerBound]) }
        }
        return short.trimmed
    }

    static func fetch<T: Decodable>(_ url: URL) async throws -> T? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Shelf/1.0 (personal ebook manager)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
