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
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        var books: [BookFile] = []
        var sdrs: [URL] = []
        let walker = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        while let url = walker?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                if url.pathExtension.lowercased() == "sdr" { sdrs.append(url); walker?.skipDescendants() }
            } else if Formats.isBook(url.lastPathComponent) {
                books.append(BookFile(url: url, size: Int64(values?.fileSize ?? 0),
                                      modified: values?.contentModificationDate ?? .distantPast))
            }
        }
        return (books, sdrs)
    }

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
        var total: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let file = walker?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
