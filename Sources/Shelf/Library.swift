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
        ThumbnailCache.shared.removeAll()
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

// MARK: - Importer (runs off the main thread)

enum Importer {
    struct Result {
        var books: [Book] = []
        var added = 0, merged = 0, skipped = 0
        var errors: [String] = []
    }

    /// A group of files that represent one book (e.g. a Calibre book folder with several formats).
    struct Candidate {
        var files: [URL]
        var opf: URL?
        var cover: URL?
    }

    static func run(urls: [URL], root: URL, existing: [Book], progress: @escaping (Int, Int) -> Void) -> Result {
        let candidates = collect(urls)
        var result = Result()
        var byKey = Dictionary(existing.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { a, _ in a })
        var touched: [UUID: Book] = [:]
        let fm = FileManager.default

        for (n, c) in candidates.enumerated() {
            progress(n + 1, candidates.count)

            var meta = ExtractedMetadata()
            if let opf = c.opf, let data = try? Data(contentsOf: opf) { meta = Metadata.opf(data) }
            if let cover = c.cover { meta.cover = try? Data(contentsOf: cover) }
            let ordered = c.files.sorted { a, b in
                (Book.readingOrder.firstIndex(of: a.pathExtension.lowercased()) ?? 99)
                    < (Book.readingOrder.firstIndex(of: b.pathExtension.lowercased()) ?? 99)
            }
            for f in ordered where meta.title == nil || meta.author?.isEmpty ?? true || meta.cover == nil {
                meta.merge(Metadata.extract(from: f))
            }

            let title = meta.title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? ordered[0].deletingPathExtension().lastPathComponent
            let author = meta.author?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown"
            var book = Book(title: title, author: author, series: meta.series, seriesIndex: meta.seriesIndex,
                            tags: meta.tags, summary: meta.summary, folder: "", files: [])

            // Already in library? Add any missing formats to it.
            if var match = byKey[book.dedupeKey] {
                let have = Set(match.files.map { ($0 as NSString).pathExtension.lowercased() })
                let new = c.files.filter { !have.contains($0.pathExtension.lowercased()) }
                if new.isEmpty { result.skipped += 1; continue }
                for f in new {
                    let name = uniqueName(f.lastPathComponent, in: root.appendingPathComponent(match.folder))
                    do {
                        try fm.copyItem(at: f, to: root.appendingPathComponent(match.folder).appendingPathComponent(name))
                        match.files.append(name)
                        result.merged += 1
                    } catch { result.errors.append("\(f.lastPathComponent): \(error.localizedDescription)") }
                }
                byKey[match.dedupeKey] = match
                touched[match.id] = match
                continue
            }

            // New book folder: Author/Title
            let authorDir = sanitize(author.components(separatedBy: " & ").first ?? author)
            var folder = "\(authorDir)/\(sanitize(title))"
            var suffix = 2
            while fm.fileExists(atPath: root.appendingPathComponent(folder).path) {
                folder = "\(authorDir)/\(sanitize(title)) (\(suffix))"; suffix += 1
            }
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                for f in c.files {
                    let name = uniqueName(sanitize(title) + "." + f.pathExtension.lowercased(), in: dir)
                    try fm.copyItem(at: f, to: dir.appendingPathComponent(name))
                    book.files.append(name)
                }
                if let cover = meta.cover, NSImage(data: cover) != nil {
                    let data = NSImage(data: cover).flatMap(Metadata.jpeg) ?? cover
                    try data.write(to: dir.appendingPathComponent("cover.jpg"))
                    book.hasCover = true
                }
                book.folder = folder
                byKey[book.dedupeKey] = book
                touched[book.id] = book
                result.added += 1
            } catch {
                try? fm.removeItem(at: dir)
                result.errors.append("\(title): \(error.localizedDescription)")
            }
        }
        result.books = Array(touched.values)
        return result
    }

    /// Walk the dropped URLs. A folder containing metadata.opf (Calibre-style) is one book with all its formats.
    static func collect(_ urls: [URL]) -> [Candidate] {
        let fm = FileManager.default
        var loose: [URL] = []
        var groups: [URL: Candidate] = [:]

        func consider(_ file: URL) {
            guard bookExtensions.contains(file.pathExtension.lowercased()) else { return }
            let dir = file.deletingLastPathComponent()
            let opf = dir.appendingPathComponent("metadata.opf")
            if fm.fileExists(atPath: opf.path) {
                var g = groups[dir] ?? Candidate(files: [], opf: opf)
                let cover = dir.appendingPathComponent("cover.jpg")
                if fm.fileExists(atPath: cover.path) { g.cover = cover }
                g.files.append(file)
                groups[dir] = g
            } else {
                loose.append(file)
            }
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                      options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let f = e?.nextObject() as? URL {
                    if (try? f.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { consider(f) }
                }
            } else {
                consider(url)
            }
        }
        return groups.values.sorted { $0.files[0].path < $1.files[0].path } + loose.map { Candidate(files: [$0]) }
    }

    static func sanitize(_ s: String) -> String {
        var out = s.replacingOccurrences(of: "[/:\\\\?*\"<>|]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasPrefix(".") { out.removeFirst() }
        if out.count > 80 { out = String(out.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return out.isEmpty ? "Untitled" : out
    }

    static func uniqueName(_ name: String, in dir: URL) -> String {
        let fm = FileManager.default
        var candidate = name
        var n = 2
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path) {
            candidate = "\(base) \(n).\(ext)"; n += 1
        }
        return candidate
    }
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Thumbnails

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func removeAll() { cache.removeAllObjects() }

    func image(at url: URL, key: String) async -> NSImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 480,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: key as NSString) }
        return image
    }
}
