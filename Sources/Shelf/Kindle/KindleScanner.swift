import Foundation

enum KindleScanner {
    struct Result {
        var items: [KindleItem] = []
        var orphans: [URL] = []
        var orphanBytes: Int64 = 0
    }

    private struct BookFile {
        let url: URL
        let size: Int64
        let modified: Date
        var dir: URL { url.deletingLastPathComponent() }
        var stem: String { url.deletingPathExtension().lastPathComponent }
    }

    static func scan(_ documents: URL) -> Result {
        let (books, sdrs) = listFiles(in: documents)
        let items = books.map { item(for: $0, sidecars: sdrs, documents: documents) }
        let orphans = orphans(sdrs, books: books)
        return Result(items: items, orphans: orphans, orphanBytes: orphans.reduce(0) { $0 + folderSize($1) })
    }

    private static func listFiles(in documents: URL) -> (books: [BookFile], sdrs: [URL]) {
        let all = FileManager.default.contentsRecursively(of: documents, descendingInto: { !isSidecar($0) })
        let books = all.filter { !$0.isDirectory && Formats.isBook($0.lastPathComponent) }.map { url in
            BookFile(url: url, size: url.fileSize,
                     modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
        }
        return (books, all.filter(isSidecar))
    }

    private static func isSidecar(_ url: URL) -> Bool { url.isDirectory && url.pathExtension.lowercased() == "sdr" }

    private static func item(for file: BookFile, sidecars sdrs: [URL], documents: URL) -> KindleItem {
        let meta = Metadata.extract(from: file.url, cover: false)
        let title = meta.title.flatMap { $0 == file.stem ? nil : $0 } ?? KindleFiles.prettyTitle(file.stem)
        let author = meta.author ?? ""
        return KindleItem(
            url: file.url, title: title, author: author, size: file.size, modified: file.modified,
            sidecars: sdrs.filter {
                $0.deletingLastPathComponent() == file.dir
                    && KindleFiles.sidecar($0.deletingPathExtension().lastPathComponent, belongsTo: file.stem)
            },
            dedupeKey: Book.dedupeKey(title: title, author: author),
            isPurchase: KindleFiles.isPurchase(file.url, documents: documents))
    }

    private static func orphans(_ sdrs: [URL], books: [BookFile]) -> [URL] {
        let byDir = Dictionary(grouping: books, by: \.dir)
        return sdrs.filter { sdr in
            let siblings = byDir[sdr.deletingLastPathComponent()] ?? []
            return KindleFiles.isOrphan(sdr.deletingPathExtension().lastPathComponent,
                                        bookStems: Set(siblings.map(\.stem)),
                                        asins: Set(siblings.compactMap { KindleFiles.asin($0.stem) }))
        }
    }

    private static func folderSize(_ url: URL) -> Int64 {
        FileManager.default.contentsRecursively(of: url).reduce(0) { $0 + $1.fileSize }
    }
}
