import Foundation
import Observation

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

    func state(for book: Book) -> LookupState? {
        if let state = states[book.id] { return state }
        if let hit = cache[Self.key(book)] { return hit.map(LookupState.found) ?? .notFound }
        return nil
    }

    func load(_ book: Book, files: [URL], force: Bool = false) {
        if !force, let state = state(for: book), state != .loading { states[book.id] = state; return }
        guard states[book.id] != .loading else { return }
        states[book.id] = .loading
        Task {
            do {
                var isbn = book.isbn
                if isbn == nil { isbn = await Task.detached { Self.isbn(in: files) }.value }
                let info = try await BookLookup.lookup(title: book.title, author: book.firstAuthor, isbn: isbn)
                cache[Self.key(book)] = .some(info)
                states[book.id] = info.map(LookupState.found) ?? .notFound
                persist()
            } catch {
                states[book.id] = .failed(error.localizedDescription)
            }
        }
    }

    private static func key(_ book: Book) -> String { book.isbn ?? book.dedupeKey }

    private nonisolated static func isbn(in files: [URL]) -> String? {
        files.lazy.compactMap { Metadata.extract(from: $0, cover: false).isbn }.first
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }
}
