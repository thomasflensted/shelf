import AppKit
import Foundation

enum Importer {
    struct Result {
        var books: [Book] = []
        var added = 0, merged = 0, skipped = 0
        var errors: [String] = []

        var summary: String {
            var parts = ["Added \(counted(added, "book"))"]
            if merged > 0 { parts.append(counted(merged, "new format")) }
            if skipped > 0 { parts.append("\(skipped) already in library") }
            return parts.joined(separator: ", ")
        }
    }

    struct Candidate {
        var files: [URL]
        var opf: URL?
        var cover: URL?
    }

    static func run(urls: [URL], root: URL, existing: [Book], progress: @escaping (Int, Int) -> Void) -> Result {
        let candidates = collect(urls)
        var result = Result()
        var byKey = Dictionary(existing.map { ($0.dedupeKey, $0) }, uniquingKeysWith: { first, _ in first })
        var touched: [Book.ID: Book] = [:]

        for (n, candidate) in candidates.enumerated() {
            progress(n + 1, candidates.count)
            let meta = metadata(for: candidate)
            let book = newBook(from: meta, fallbackTitle: candidate.files[0].deletingPathExtension().lastPathComponent)
            do {
                let saved: Book
                if let match = byKey[book.dedupeKey] {
                    let newFiles = missingFormats(candidate.files, in: match)
                    guard !newFiles.isEmpty else { result.skipped += 1; continue }
                    saved = try addFiles(newFiles, to: match, root: root)
                    result.merged += newFiles.count
                } else {
                    saved = try create(book, files: candidate.files, cover: meta.cover, root: root)
                    result.added += 1
                }
                byKey[saved.dedupeKey] = saved
                touched[saved.id] = saved
            } catch {
                result.errors.append("\(book.title): \(error.localizedDescription)")
            }
        }
        result.books = Array(touched.values)
        return result
    }

    static func newBook(from meta: ExtractedMetadata, fallbackTitle: String) -> Book {
        Book(title: meta.title?.trimmed.nonEmpty ?? fallbackTitle,
             author: meta.author?.trimmed.nonEmpty ?? Book.unknownAuthor,
             series: meta.series, seriesIndex: meta.seriesIndex, tags: meta.tags,
             summary: meta.summary, isbn: meta.isbn, folder: "", files: [])
    }

    static func missingFormats(_ files: [URL], in book: Book) -> [URL] {
        let have = Set(book.files.map(Formats.ext))
        return files.filter { !have.contains(Formats.ext($0.lastPathComponent)) }
    }

    static func folderName(for book: Book) -> String {
        "\(book.firstAuthor.safeFileName)/\(book.title.safeFileName)"
    }

    static func fileName(for book: Book, copying file: URL) -> String {
        book.title.safeFileName + "." + Formats.ext(file.lastPathComponent)
    }

    static func collect(_ urls: [URL]) -> [Candidate] {
        let fm = FileManager.default
        var loose: [URL] = []
        var calibreFolders: [URL: Candidate] = [:]

        func consider(_ file: URL) {
            guard Formats.isBook(file.lastPathComponent) else { return }
            let dir = file.deletingLastPathComponent()
            let opf = dir.appendingPathComponent("metadata.opf")
            guard fm.fileExists(atPath: opf.path) else { loose.append(file); return }
            var group = calibreFolders[dir] ?? Candidate(files: [], opf: opf)
            let cover = dir.appendingPathComponent(Book.coverFileName)
            if fm.fileExists(atPath: cover.path) { group.cover = cover }
            group.files.append(file)
            calibreFolders[dir] = group
        }

        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            guard isDir.boolValue else { consider(url); continue }
            let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey],
                                       options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let file = walker?.nextObject() as? URL {
                if (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { consider(file) }
            }
        }
        return calibreFolders.values.sorted { $0.files[0].path < $1.files[0].path } + loose.map { Candidate(files: [$0]) }
    }

    private static func metadata(for candidate: Candidate) -> ExtractedMetadata {
        var meta = candidate.opf.flatMap { try? Data(contentsOf: $0) }.map { Metadata.opf($0) } ?? ExtractedMetadata()
        if let cover = candidate.cover { meta.cover = try? Data(contentsOf: cover) }
        for file in Formats.sorted(candidate.files, by: Formats.readingOrder, name: \.lastPathComponent) where !meta.isComplete {
            meta.merge(Metadata.extract(from: file))
        }
        return meta
    }

    private static func availableFolder(for book: Book, root: URL) -> String {
        let base = folderName(for: book)
        var folder = base, n = 2
        while FileManager.default.fileExists(atPath: root.appendingPathComponent(folder).path) {
            folder = "\(base) (\(n))"
            n += 1
        }
        return folder
    }

    private static func addFiles(_ files: [URL], to book: Book, root: URL) throws -> Book {
        var book = book
        for file in files {
            let name = fileName(for: book, copying: file)
            try FileManager.default.copyItem(at: file, to: book.folderURL(in: root).appendingPathComponent(name))
            book.files.append(name)
        }
        return book
    }

    private static func create(_ book: Book, files: [URL], cover: Data?, root: URL) throws -> Book {
        var book = book
        book.folder = availableFolder(for: book, root: root)
        let dir = book.folderURL(in: root)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            book = try addFiles(files, to: book, root: root)
            if let jpeg = cover.flatMap(NSImage.init(data:)).flatMap(Metadata.jpeg) {
                try jpeg.write(to: book.coverURL(in: root))
                book.hasCover = true
            }
            return book
        } catch {
            try? FileManager.default.removeItem(at: dir)
            throw error
        }
    }
}
