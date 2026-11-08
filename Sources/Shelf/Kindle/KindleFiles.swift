import Foundation

enum KindleFiles {
    private static let asinSuffix = "_([A-Z0-9]{10})(_sample)?$"

    static func asin(_ stem: String) -> String? {
        guard let match = stem.range(of: asinSuffix, options: .regularExpression) else { return nil }
        let id = stem[match].split(separator: "_").first.map(String.init) ?? ""
        return id.contains(where: \.isNumber) ? id : nil
    }

    static func prettyTitle(_ stem: String) -> String {
        let isSample = stem.hasSuffix("_sample")
        var title = stem
        if let match = title.range(of: asinSuffix, options: .regularExpression) { title.removeSubrange(match) }
        title = title.replacingOccurrences(of: "_ ", with: ": ").replacingOccurrences(of: "_", with: " ")
        return movingTrailingArticle(title) + (isSample ? " (sample)" : "")
    }

    static func fileStem(for book: Book) -> String { "\(book.title) - \(book.author)".safeFileName }

    static func sendable(_ books: [Book]) -> (files: [(book: Book, file: String)], skipped: [Book]) {
        var files: [(book: Book, file: String)] = []
        var skipped: [Book] = []
        for book in books {
            if let file = Formats.best(of: book.files, in: Formats.kindleOrder) { files.append((book, file)) } else { skipped.append(book) }
        }
        return (files, skipped)
    }

    // Amazon books often have a second, short-named sidecar ("Title_ASIN.sdr") next to the full-named one.
    static func sidecar(_ sdrStem: String, belongsTo bookStem: String) -> Bool {
        sdrStem == bookStem || (asin(bookStem) != nil && asin(sdrStem) == asin(bookStem))
    }

    static func isOrphan(_ sdrStem: String, bookStems: Set<String>, asins: Set<String>) -> Bool {
        if bookStems.contains(sdrStem) { return false }
        if let id = asin(sdrStem), asins.contains(id) { return false }
        return true
    }

    static func isPurchase(_ url: URL, documents: URL) -> Bool {
        asin(url.deletingPathExtension().lastPathComponent) != nil
            && url.path.hasPrefix(documents.appendingPathComponent("Downloads").path + "/")
    }

    private static func movingTrailingArticle(_ title: String) -> String {
        let cut = [title.range(of: ": "), title.range(of: " (")].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
        var head = cut.map { String(title[..<$0.lowerBound]) } ?? title
        let tail = cut.map { String(title[$0.lowerBound...]) } ?? ""
        for article in ["The", "A", "An"] where head.hasSuffix(", \(article)") {
            head = article + " " + head.dropLast(article.count + 2)
        }
        return head + tail
    }
}
