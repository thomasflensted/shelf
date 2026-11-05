import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class Library {
    private(set) var root: URL
    private(set) var books: [Book] = []
    var importStatus: String?
    var lastError: String?

    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Books")
    static let calibreRoot = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Calibre Library")

    init() {
        if let path = UserDefaults.standard.string(forKey: "libraryPath") {
            root = URL(fileURLWithPath: path)
        } else {
            root = Library.defaultRoot
        }
        load()
    }

    private var indexURL: URL { root.appendingPathComponent("library.json") }

    func url(for book: Book) -> URL { root.appendingPathComponent(book.folder, isDirectory: true) }
    func fileURL(_ book: Book, _ file: String) -> URL { url(for: book).appendingPathComponent(file) }
    func coverURL(_ book: Book) -> URL { url(for: book).appendingPathComponent("cover.jpg") }

    // MARK: Persistence

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL) else { books = []; return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        books = (try? decoder.decode([Book].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try encoder.encode(books).write(to: indexURL, options: .atomic)
        } catch {
            lastError = "Couldn't save library: \(error.localizedDescription)"
        }
    }

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use as Library"
        panel.message = "Choose a folder to keep your books in. An existing Shelf library will be opened."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        root = url
        UserDefaults.standard.set(url.path, forKey: "libraryPath")
        load()
    }

    // MARK: Editing

    func update(_ book: Book, newCover: URL? = nil) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        var b = book
        if let newCover, let image = NSImage(contentsOf: newCover), let jpeg = Metadata.jpeg(image) {
            do {
                try jpeg.write(to: coverURL(b), options: .atomic)
                b.hasCover = true
                b.coverVersion += 1
            } catch {
                lastError = "Couldn't save cover: \(error.localizedDescription)"
            }
        }
        books[i] = b
        save()
    }

    func trash(_ ids: Set<Book.ID>) {
        let fm = FileManager.default
        for book in books where ids.contains(book.id) {
            let folder = url(for: book)
            try? fm.trashItem(at: folder, resultingItemURL: nil)
            // Remove the author folder if it's now empty.
            let parent = folder.deletingLastPathComponent()
            if parent != root, (try? fm.contentsOfDirectory(atPath: parent.path))?.filter({ !$0.hasPrefix(".") }).isEmpty == true {
                try? fm.removeItem(at: parent)
            }
        }
        books.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: Opening

    func open(_ book: Book, file: String? = nil) {
        guard let f = file ?? book.preferredFiles.first else { return }
        NSWorkspace.shared.open(fileURL(book, f))
    }

    func reveal(_ books: [Book]) {
        NSWorkspace.shared.activateFileViewerSelecting(books.compactMap { b in b.preferredFiles.first.map { fileURL(b, $0) } })
    }

    // MARK: Importing

    func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose books, or a folder (such as a Calibre library) to import everything in it."
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        importItems(panel.urls)
    }

    func importItems(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let root = self.root
        let existing = books
        importStatus = "Importing…"
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Importer.run(urls: urls, root: root, existing: existing) { done, total in
                    Task { @MainActor in self.importStatus = "Importing \(done) of \(total)…" }
                }
            }.value
            for b in result.books {
                if let i = books.firstIndex(where: { $0.id == b.id }) { books[i] = b } else { books.append(b) }
            }
            save()
            var msg = "Added \(result.added) book\(result.added == 1 ? "" : "s")"
            if result.merged > 0 { msg += ", \(result.merged) new format\(result.merged == 1 ? "" : "s")" }
            if result.skipped > 0 { msg += ", \(result.skipped) already in library" }
            importStatus = msg
            if !result.errors.isEmpty { lastError = result.errors.prefix(5).joined(separator: "\n") }
            clearStatusSoon()
        }
    }

    private func clearStatusSoon() {
        let current = importStatus
        Task {
            try? await Task.sleep(for: .seconds(6))
            if importStatus == current { importStatus = nil }
        }
    }
}
