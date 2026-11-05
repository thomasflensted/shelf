import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class Library {
    private(set) var root: URL
    private(set) var books: [Book] = []
    let feedback = Feedback()

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

    var hasCalibreLibrary: Bool { FileManager.default.fileExists(atPath: Library.calibreRoot.path) }

    private var indexURL: URL { root.appendingPathComponent("library.json") }

    func fileURL(_ book: Book, _ file: String) -> URL { book.folderURL(in: root).appendingPathComponent(file) }
    func coverURL(_ book: Book) -> URL { book.coverURL(in: root) }

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
            feedback.fail(["Couldn't save library: \(error.localizedDescription)"])
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

    func update(_ book: Book, newCover: URL? = nil) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        var b = book
        if let newCover, let image = NSImage(contentsOf: newCover), let jpeg = Metadata.jpeg(image) {
            do {
                try jpeg.write(to: coverURL(b), options: .atomic)
                b.hasCover = true
                b.coverVersion += 1
            } catch {
                feedback.fail(["Couldn't save cover: \(error.localizedDescription)"])
            }
        }
        books[i] = b
        save()
    }

    func trash(_ ids: Set<Book.ID>) {
        let fm = FileManager.default
        for book in books where ids.contains(book.id) {
            let folder = book.folderURL(in: root)
            try? fm.trashItem(at: folder, resultingItemURL: nil)
            removeIfEmpty(folder.deletingLastPathComponent())
        }
        books.removeAll { ids.contains($0.id) }
        save()
    }

    func reveal(_ books: [Book]) {
        NSWorkspace.shared.activateFileViewerSelecting(books.compactMap { b in b.preferredFiles.first.map { fileURL(b, $0) } })
    }

    func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose books, or a folder (such as a Calibre library) to import everything in it."
        panel.prompt = "Add"
        guard panel.runModal() == .OK else { return }
        importItems(panel.urls)
    }

    func importCalibreLibrary() { importItems([Library.calibreRoot]) }

    func importItems(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let root = self.root
        let existing = books
        feedback.progress("Importing…")
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Importer.run(urls: urls, root: root, existing: existing) { done, total in
                    Task { @MainActor in self.feedback.progress("Importing \(done) of \(total)…") }
                }
            }.value
            for book in result.books {
                if let i = books.firstIndex(where: { $0.id == book.id }) { books[i] = book } else { books.append(book) }
            }
            save()
            feedback.done(result.summary)
            feedback.fail(Array(result.errors.prefix(5)))
        }
    }

    private func removeIfEmpty(_ authorFolder: URL) {
        guard authorFolder != root,
              (try? FileManager.default.contentsOfDirectory(atPath: authorFolder.path))?.allSatisfy({ $0.hasPrefix(".") }) == true
        else { return }
        try? FileManager.default.removeItem(at: authorFolder)
    }
}
