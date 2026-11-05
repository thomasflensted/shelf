import Foundation

struct MatchKeys {
    private let dedupeKeys: Set<String>
    private let stems: Set<String>

    init(books: [Book]) {
        dedupeKeys = Set(books.map(\.dedupeKey))
        stems = Set(books.map { KindleFiles.fileStem(for: $0).lowercased() })
    }

    init(items: [KindleItem]) {
        dedupeKeys = Set(items.map(\.dedupeKey))
        stems = Set(items.map { $0.stem.lowercased() })
    }

    func contains(_ book: Book) -> Bool {
        dedupeKeys.contains(book.dedupeKey) || stems.contains(KindleFiles.fileStem(for: book).lowercased())
    }

    func contains(_ item: KindleItem) -> Bool {
        dedupeKeys.contains(item.dedupeKey) || stems.contains(item.stem.lowercased())
    }
}
