import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(Kindle.self) private var kindle
    @State private var search = ""
    @State private var selection = Set<Book.ID>()
    @State private var sortOrder = SortOption.added.comparators
    @AppStorage("viewMode") private var viewMode = ViewMode.grid
    @AppStorage("showInspector") private var showInspector = true
    @State private var editing: Book?
    @State private var pendingTrash: [Book.ID] = []
    @State private var dropTargeted = false

    private var visible: [Book] {
        let query = search.trimmed
        let filtered = query.isEmpty ? library.books : library.books.filter { $0.matches(query) }
        return filtered.sorted(using: sortOrder)
    }

    private var selectedBooks: [Book] { library.books.filter { selection.contains($0.id) } }

    var body: some View {
        Group {
            if library.books.isEmpty {
                emptyState
            } else if viewMode == .grid {
                BookGrid(books: visible, selection: $selection, edit: edit, menu: menu)
            } else {
                BookTable(books: visible, selection: $selection, sortOrder: $sortOrder, edit: edit, menu: menu)
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.importItems(urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StatusBar(message: statusMessage, busy: library.feedback.isBusy || kindle.feedback.isBusy)
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Title, author, series, tag")
        .navigationTitle("Shelf")
        .navigationSubtitle(counted(library.books.count, "book"))
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            inspector.inspectorColumnWidth(min: 260, ideal: 300, max: 440)
        }
        .sheet(item: $editing) { BookEditor(book: $0) }
        .confirmationDialog(trashPrompt, isPresented: Binding(isNotEmpty: $pendingTrash)) {
            Button("Move to Trash", role: .destructive) {
                library.trash(Set(pendingTrash))
                selection.subtract(pendingTrash)
                pendingTrash = []
            }
        } message: {
            Text("The book files will be moved to the Trash.")
        }
        .errorAlert("Something went wrong", library.feedback)
    }

    private var statusMessage: String? {
        if let status = library.feedback.status ?? kindle.feedback.status { return status }
        if !search.isEmpty { return "\(visible.count) of \(counted(library.books.count, "book"))" }
        if !selection.isEmpty { return "\(selection.count) selected" }
        return nil
    }

    @ViewBuilder
    private var inspector: some View {
        if selection.count == 1, let book = selectedBooks.first {
            BookInspector(book: book, coverURL: library.coverURL(book)) { editing = book }
        } else {
            ContentUnavailableView(selection.isEmpty ? "No Selection" : "\(selection.count) Books Selected",
                                   systemImage: "book",
                                   description: Text(selection.isEmpty ? "Click a book to see its details." : ""))
        }
    }

    private var trashPrompt: String {
        if pendingTrash.count == 1, let book = library.books.first(where: { $0.id == pendingTrash[0] }) {
            return "Move “\(book.title)” to the Trash?"
        }
        return "Move \(pendingTrash.count) books to the Trash?"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { library.importItems(Panels.chooseBooks()) } label: { Label("Add Books", systemImage: "plus") }
                .help("Add books (⌘O) — or drop files onto the window")

            Button { editing = selectedBooks.first } label: { Label("Edit", systemImage: "pencil") }
                .keyboardShortcut("e")
                .disabled(selection.count != 1)
                .help("Edit title, author, cover… (⌘E)")

            if kindle.connected {
                Button { kindle.send(selectedBooks, from: library) } label: {
                    Label("Send to Kindle", systemImage: "square.and.arrow.down.on.square")
                }
                .keyboardShortcut("k")
                .disabled(selection.isEmpty)
                .help("Copy selected books to \(kindle.name) (⌘K)")
            }

            Button { pendingTrash = Array(selection) } label: { Label("Move to Trash", systemImage: "trash") }
                .keyboardShortcut(.delete)
                .disabled(selection.isEmpty)
                .help("Move to Trash (⌘⌫)")

            Menu {
                Picker("Sort By", selection: Binding(get: { SortOption(sortOrder) }, set: { sortOrder = $0.comparators })) {
                    ForEach(SortOption.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }

            Button { showInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
                .keyboardShortcut("i")
                .help("Show or hide book info (⌘I)")

            Picker("View", selection: $viewMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag(ViewMode.grid)
                Label("List", systemImage: "list.bullet").tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Drop ebook files or folders here, or add them with ⌘O.")
        } actions: {
            Button("Add Books…") { library.importItems(Panels.chooseBooks()) }
            if library.hasCalibreLibrary {
                Button("Import Calibre Library") { library.importCalibreLibrary() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func edit(_ ids: Set<Book.ID>) {
        guard ids.count == 1 else { return }
        editing = library.books.first { ids.contains($0.id) }
    }

    @ViewBuilder
    private func menu(_ ids: Set<Book.ID>) -> some View {
        let books = library.books.filter { ids.contains($0.id) }
        if !books.isEmpty {
            if books.count == 1, let book = books.first {
                Button("Edit…") { editing = book }
                Divider()
            }
            Button("Show in Finder") { library.reveal(books) }
            if kindle.connected {
                Divider()
                Button("Send to \(kindle.name)") { kindle.send(books, from: library) }
                let onDevice = books.flatMap { kindle.items(for: $0) }
                if !onDevice.isEmpty {
                    Button("Remove from \(kindle.name)") { kindle.remove(onDevice) }
                }
            }
            Divider()
            Button("Move to Trash…", role: .destructive) { pendingTrash = Array(ids) }
        }
    }
}
