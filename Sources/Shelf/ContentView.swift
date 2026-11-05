import SwiftUI

struct ContentView: View {
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

// MARK: - Grid

struct BookGrid<Menu: View>: View {
    @Environment(Library.self) private var library
    @Environment(Kindle.self) private var kindle
    let books: [Book]
    @Binding var selection: Set<Book.ID>
    let open: (Set<Book.ID>) -> Void
    let menu: (Set<Book.ID>) -> Menu
    @State private var anchor: Book.ID?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 180), spacing: 22, alignment: .top)], spacing: 26) {
                ForEach(books) { book in
                    BookCell(book: book, selected: selection.contains(book.id), coverURL: library.coverURL(book),
                             onKindle: kindle.contains(book), kindleName: kindle.name)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { open([book.id]) }
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
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            if selection.contains(book.id) { selection.remove(book.id) } else { selection.insert(book.id) }
            anchor = book.id
        } else if mods.contains(.shift), let anchor,
                  let a = books.firstIndex(where: { $0.id == anchor }),
                  let b = books.firstIndex(where: { $0.id == book.id }) {
            selection = Set(books[min(a, b)...max(a, b)].map(\.id))
        } else {
            selection = [book.id]
            anchor = book.id
        }
    }
}

struct BookCell: View {
    let book: Book
    let selected: Bool
    let coverURL: URL
    let onKindle: Bool
    let kindleName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book, coverURL: coverURL)
                .aspectRatio(2 / 3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                        .padding(-4)
                )
                .overlay(alignment: .bottomTrailing) {
                    if onKindle {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 18))
                            .shadow(radius: 2)
                            .padding(5)
                            .help("On \(kindleName)")
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(book.title).font(.callout.weight(.medium)).lineLimit(2)
                Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}

struct CoverView: View {
    let book: Book
    /// Passed in explicitly: Table cells don't reliably inherit environment objects.
    let coverURL: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: book.coverKey) {
            image = book.hasCover ? await ThumbnailCache.shared.image(at: coverURL, key: book.coverKey) : nil
        }
    }

    private var placeholder: some View {
        let hue = Double(book.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.35, brightness: 0.55),
                                    Color(hue: hue, saturation: 0.45, brightness: 0.35)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Text(book.title).font(.system(size: 13, weight: .semibold, design: .serif))
                Text(book.author).font(.system(size: 10))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.92))
            .padding(10)
            .minimumScaleFactor(0.5)
        }
    }
}

// MARK: - List

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
