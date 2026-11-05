import SwiftUI

struct BookGrid<Menu: View>: View {
    @Environment(Library.self) private var library
    @Environment(Kindle.self) private var kindle
    let books: [Book]
    @Binding var selection: Set<Book.ID>
    let edit: (Set<Book.ID>) -> Void
    let menu: (Set<Book.ID>) -> Menu
    @State private var anchor: Book.ID?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 22, alignment: .top)], spacing: 26) {
                ForEach(books) { book in
                    BookCell(book: book, selected: selection.contains(book.id), coverURL: library.coverURL(book),
                             onKindle: kindle.contains(book), kindleName: kindle.name)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { edit([book.id]) }
                        .simultaneousGesture(TapGesture().onEnded { click(book) })
                        .contextMenu { menu(selection.contains(book.id) ? selection : [book.id]) }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onTapGesture { selection = [] }
    }

    private func click(_ book: Book) {
        let modifiers = NSEvent.modifierFlags
        (selection, anchor) = GridSelection.click(book.id, in: books.map(\.id), selection: selection, anchor: anchor,
                                                  command: modifiers.contains(.command), shift: modifiers.contains(.shift))
    }
}
