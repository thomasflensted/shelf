import Foundation

struct Book: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var author: String
    var series: String?
    var seriesIndex: Double?
    var tags: [String] = []
    var summary: String?
    var added = Date()
    /// Folder relative to the library root.
    var folder: String
    /// File names inside `folder`.
    var files: [String]
    var hasCover = false
    var coverVersion = 0

    var coverKey: String { "\(id)-\(coverVersion)-\(hasCover)" }

    var formats: String {
        files.map { ($0 as NSString).pathExtension.uppercased() }.sorted().joined(separator: ", ")
    }

    /// "Christie, Agatha" style sort key for the first author.
    var authorSort: String {
        let first = author.components(separatedBy: " & ").first ?? author
        let parts = first.split(separator: " ")
        guard parts.count > 1, let last = parts.last else { return first }
        return "\(last), \(parts.dropLast().joined(separator: " "))"
    }

    var seriesLabel: String {
        guard let series, !series.isEmpty else { return "" }
        guard let i = seriesIndex else { return series }
        let n = i.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(i)) : String(i)
        return "\(series) #\(n)"
    }

    var seriesSort: String { series.map { "\($0) \(String(format: "%08.2f", seriesIndex ?? 0))" } ?? "" }

    func matches(_ query: String) -> Bool {
        let hay = [title, author, series ?? "", tags.joined(separator: " ")].joined(separator: " ")
        return query.split(separator: " ").allSatisfy { hay.localizedCaseInsensitiveContains($0) }
    }

    static let readingOrder = ["epub", "azw3", "mobi", "azw", "pdf", "cbz", "cbr", "fb2", "djvu", "txt", "rtf"]

    /// Files ordered by how good they are to open.
    var preferredFiles: [String] {
        files.sorted { a, b in
            let ia = Book.readingOrder.firstIndex(of: (a as NSString).pathExtension.lowercased()) ?? 99
            let ib = Book.readingOrder.firstIndex(of: (b as NSString).pathExtension.lowercased()) ?? 99
            return ia < ib
        }
    }

    var dedupeKey: String {
        func norm(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        // Author words sorted, so "Bryson, Bill" and "Bill Bryson" match.
        let authorKey = author.lowercased()
            .split { !($0.isLetter || $0.isNumber) }
            .sorted()
            .joined()
        return norm(title) + "|" + authorKey
    }
}

let bookExtensions: Set<String> = ["epub", "pdf", "mobi", "azw", "azw3", "kfx", "cbz", "cbr", "fb2", "djvu", "txt", "rtf", "docx", "lit", "prc"]
