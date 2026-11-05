import SwiftUI

struct LibraryView: View {
    @Environment(Library.self) private var library
    @Environment(Kindle.self) private var kindle
    @State private var search = ""
    @State private var selection = Set<Book.ID>()
    @State private var sortOrder = [KeyPathComparator(\Book.added, order: .reverse)]
    @AppStorage("viewMode") private var viewMode = "grid"
    @State private var editing: Book?
    @State private var pendingTrash: Set<Book.ID> = []
    @State private var dropTargeted = false
    @AppStorage("showInspector") private var showInspector = true

    private var visible: [Book] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? library.books : library.books.filter { $0.matches(q) }
        return filtered.sorted(using: sortOrder)
    }

    private var selectedBooks: [Book] { library.books.filter { selection.contains($0.id) } }

    var body: some View {
        Group {
            if library.books.isEmpty {
                emptyState
            } else if viewMode == "grid" {
                BookGrid(books: visible, selection: $selection, open: open, menu: menu)
            } else {
                BookTable(books: visible, selection: $selection, sortOrder: $sortOrder, open: open, menu: menu)
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
        .safeAreaInset(edge: .bottom, spacing: 0) { statusBar }
        .searchable(text: $search, placement: .toolbar, prompt: "Title, author, series, tag")
        .navigationTitle("Shelf")
        .navigationSubtitle("\(library.books.count) books")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            inspector.inspectorColumnWidth(min: 260, ideal: 300, max: 440)
        }
        .sheet(item: $editing) { BookEditor(book: $0) }
        .confirmationDialog(trashPrompt, isPresented: Binding(get: { !pendingTrash.isEmpty }, set: { if !$0 { pendingTrash = [] } })) {
            Button("Move to Trash", role: .destructive) {
                library.trash(pendingTrash)
                selection.subtract(pendingTrash)
                pendingTrash = []
            }
        } message: {
            Text("The book files will be moved to the Trash.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { library.lastError != nil }, set: { if !$0 { library.lastError = nil } })) {
            Button("OK") { library.lastError = nil }
        } message: {
            Text(library.lastError ?? "")
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if selection.count == 1, let b = selectedBooks.first {
            BookInspector(book: b, coverURL: library.coverURL(b)) { editing = b }
        } else {
            ContentUnavailableView(selection.isEmpty ? "No Selection" : "\(selection.count) Books Selected",
                                   systemImage: "book",
                                   description: Text(selection.isEmpty ? "Click a book to see its details." : ""))
        }
    }

    private var trashPrompt: String {
        if pendingTrash.count == 1, let b = library.books.first(where: { pendingTrash.contains($0.id) }) {
            return "Move “\(b.title)” to the Trash?"
        }
        return "Move \(pendingTrash.count) books to the Trash?"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { library.presentAddPanel() } label: { Label("Add Books", systemImage: "plus") }
                .help("Add books (⌘O) — or drop files onto the window")

            Button { if let b = selectedBooks.first { editing = b } } label: { Label("Edit", systemImage: "pencil") }
                .keyboardShortcut("e")
                .disabled(selection.count != 1)
                .help("Edit title, author, cover… (⌘E)")

            if kindle.connected {
                Button { kindle.send(selectedBooks, from: library) } label: { Label("Send to Kindle", systemImage: "square.and.arrow.down.on.square") }
                    .keyboardShortcut("k")
                    .disabled(selection.isEmpty)
                    .help("Copy selected books to \(kindle.name) (⌘K)")
            }

            Button { pendingTrash = selection } label: { Label("Move to Trash", systemImage: "trash") }
                .keyboardShortcut(.delete)
                .disabled(selection.isEmpty)
                .help("Move to Trash (⌘⌫)")

            Menu {
                Picker("Sort By", selection: Binding(
                    get: { sortKey },
                    set: { setSort($0) }
                )) {
                    Text("Recently Added").tag("added")
                    Text("Title").tag("title")
                    Text("Author").tag("author")
                    Text("Series").tag("series")
                }
                .pickerStyle(.inline)
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }

            Button { showInspector.toggle() } label: { Label("Info", systemImage: "info.circle") }
                .keyboardShortcut("i")
                .help("Show or hide book info (⌘I)")

            Picker("View", selection: $viewMode) {
                Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                Label("List", systemImage: "list.bullet").tag("list")
            }
            .pickerStyle(.segmented)
        }
    }

    private var sortKey: String {
        switch sortOrder.first?.keyPath {
        case \Book.title: "title"
        case \Book.authorSort: "author"
        case \Book.seriesSort: "series"
        default: "added"
        }
    }

    private func setSort(_ key: String) {
        switch key {
        case "title": sortOrder = [KeyPathComparator(\Book.title)]
        case "author": sortOrder = [KeyPathComparator(\Book.authorSort), KeyPathComparator(\Book.title)]
        case "series": sortOrder = [KeyPathComparator(\Book.seriesSort), KeyPathComparator(\Book.title)]
        default: sortOrder = [KeyPathComparator(\Book.added, order: .reverse)]
        }
    }

    private var statusBar: some View {
        HStack {
            if let status = library.importStatus ?? kindle.status {
                if status.hasPrefix("Importing") || status.hasPrefix("Sending") { ProgressView().controlSize(.small) }
                Text(status)
            } else if !search.isEmpty {
                Text("\(visible.count) of \(library.books.count) books")
            } else if !selection.isEmpty {
                Text("\(selection.count) selected")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: library.importStatus == nil && kindle.status == nil && search.isEmpty && selection.isEmpty ? 0 : 26)
        .clipped()
        .background(.bar)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Books Yet", systemImage: "books.vertical")
        } description: {
            Text("Drop ebook files or folders here, or add them with ⌘O.")
        } actions: {
            Button("Add Books…") { library.presentAddPanel() }
            if FileManager.default.fileExists(atPath: Library.calibreRoot.path) {
                Button("Import Calibre Library") { library.importItems([Library.calibreRoot]) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func open(_ ids: Set<Book.ID>) {
        for b in library.books where ids.contains(b.id) { library.open(b) }
    }

    @ViewBuilder
    private func menu(_ ids: Set<Book.ID>) -> some View {
        let books = library.books.filter { ids.contains($0.id) }
        if !books.isEmpty {
            Button("Open") { open(ids) }
            if books.count == 1, let b = books.first, b.files.count > 1 {
                Menu("Open Format") {
                    ForEach(b.preferredFiles, id: \.self) { f in
                        Button((f as NSString).pathExtension.uppercased()) { library.open(b, file: f) }
                    }
                }
            }
            if books.count == 1, let b = books.first {
                Button("Edit…") { editing = b }
            }
            Divider()
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
            Button("Move to Trash…", role: .destructive) { pendingTrash = ids }
        }
    }
}
