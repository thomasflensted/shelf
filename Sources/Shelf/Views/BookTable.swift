import SwiftUI

struct BookTable<Menu: View>: View {
    @Environment(Library.self) private var library
    @Environment(Kindle.self) private var kindle
    let books: [Book]
    @Binding var selection: Set<Book.ID>
    @Binding var sortOrder: [KeyPathComparator<Book>]
    let open: (Set<Book.ID>) -> Void
    let menu: (Set<Book.ID>) -> Menu

    var body: some View {
        // Resolve per-row values here, outside the cells.
        let root = library.root
        let onKindle = Set(books.filter { kindle.contains($0) }.map(\.id))
        Table(books, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \.title) { b in
                HStack(spacing: 8) {
                    CoverView(book: b, coverURL: root.appendingPathComponent(b.folder).appendingPathComponent("cover.jpg")).frame(width: 20, height: 30).clipShape(RoundedRectangle(cornerRadius: 2))
                    Text(b.title)
                }
            }
            TableColumn("Author", value: \.authorSort) { Text($0.author) }
            TableColumn("Series", value: \.seriesSort) { Text($0.seriesLabel) }
            TableColumn("Formats") { Text($0.formats).foregroundStyle(.secondary) }
                .width(min: 60, ideal: 90)
            TableColumn("Kindle") { b in
                if onKindle.contains(b.id) { Image(systemName: "checkmark").foregroundStyle(.green) }
            }
            .width(50)
            TableColumn("Added", value: \.added) { Text($0.added, format: .dateTime.year().month().day()) }
                .width(min: 80, ideal: 100)
        }
        .contextMenu(forSelectionType: Book.ID.self) { ids in
            menu(ids)
        } primaryAction: { ids in
            open(ids)
        }
    }
}
