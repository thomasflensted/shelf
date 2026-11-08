import AppKit
import Foundation
import PDFKit

struct ExtractedMetadata {
    var title: String?
    var author: String?
    var series: String?
    var seriesIndex: Double?
    var tags: [String] = []
    var summary: String?
    var isbn: String?
    var cover: Data?

    var isComplete: Bool { title != nil && !(author?.isEmpty ?? true) && cover != nil }

    mutating func merge(_ other: ExtractedMetadata) {
        if title?.isEmpty ?? true { title = other.title }
        if author?.isEmpty ?? true { author = other.author }
        if series == nil { series = other.series; seriesIndex = other.seriesIndex }
        if tags.isEmpty { tags = other.tags }
        if summary == nil { summary = other.summary }
        if isbn == nil { isbn = other.isbn }
        if cover == nil { cover = other.cover }
    }
}

enum Metadata {
    static func extract(from url: URL, cover: Bool = true) -> ExtractedMetadata {
        var meta: ExtractedMetadata
        switch Formats.ext(url.lastPathComponent) {
        case "epub": meta = epub(url, cover: cover)
        case "mobi", "azw", "azw3", "prc": meta = Mobi.read(url, cover: cover)
        case "pdf": meta = pdf(url, cover: cover)
        default: meta = ExtractedMetadata()
        }
        if meta.title?.trimmed.isEmpty ?? true {
            meta.title = url.deletingPathExtension().lastPathComponent
        }
        return meta
    }

    static func opf(_ data: Data, baseDir: String = "", coverLoader: ((String) -> Data?)? = nil) -> ExtractedMetadata {
        guard let root = XMLTree.parse(data) else { return ExtractedMetadata() }
        let metas = Dictionary(
            root.all("meta").compactMap { node in node.attrs["name"].map { ($0, node.attrs["content"] ?? "") } },
            uniquingKeysWith: { first, _ in first })

        var m = ExtractedMetadata()
        m.title = root.first("title")?.text
        m.author = authors(root.all("creator")).joined(separator: " & ")
        m.isbn = root.all("identifier").lazy.compactMap(isbn).first
        m.tags = root.all("subject").map(\.text).filter { !$0.isEmpty }
        m.summary = root.first("description")?.text.nonEmpty?.strippingHTML
        m.series = metas["calibre:series"]
        m.seriesIndex = metas["calibre:series_index"].flatMap(Double.init)
        if let coverLoader, let href = coverHref(items: root.all("item"), coverID: metas["cover"]) {
            m.cover = coverLoader(resolve(href, against: baseDir))
        }
        return m
    }

    static func coverHref(items: [XMLTree], coverID: String?) -> String? {
        let item = items.first { ($0.attrs["properties"] ?? "").contains("cover-image") }
            ?? items.first { coverID != nil && $0.attrs["id"] == coverID }
            ?? items.first { ($0.attrs["id"] ?? "").lowercased().contains("cover") && ($0.attrs["media-type"] ?? "").hasPrefix("image/") }
        return item?.attrs["href"]?.removingPercentEncoding
    }

    static func resolve(_ href: String, against base: String) -> String {
        var parts = base.split(separator: "/").map(String.init)
        for part in href.split(separator: "/") {
            if part == ".." { _ = parts.popLast() } else if part != "." { parts.append(String(part)) }
        }
        return parts.joined(separator: "/")
    }

    static func cleanISBN(_ s: String) -> String? {
        let digits = s.uppercased().filter { $0.isNumber || $0 == "X" }
        return digits.count == 10 || digits.count == 13 ? digits : nil
    }

    static func flipName(_ name: String) -> String {
        let parts = name.components(separatedBy: ", ")
        guard parts.count == 2 else { return name }
        return "\(parts[1]) \(parts[0])"
    }

    static func jpeg(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }

    private static func authors(_ creators: [XMLTree]) -> [String] {
        let authors = creators.filter { ($0.attrs["role"] ?? "aut") == "aut" }.map(\.text).filter { !$0.isEmpty }
        return authors.isEmpty ? creators.map(\.text) : authors
    }

    private static func isbn(_ identifier: XMLTree) -> String? {
        let text = identifier.text.lowercased()
        guard identifier.attrs["scheme"]?.lowercased() == "isbn" || text.hasPrefix("urn:isbn:") else { return nil }
        return cleanISBN(text.replacingOccurrences(of: "urn:isbn:", with: ""))
    }

    private static func epub(_ url: URL, cover: Bool) -> ExtractedMetadata {
        guard let container = unzip(url, "META-INF/container.xml"),
              let opfPath = XMLTree.parse(container)?.first("rootfile")?.attrs["full-path"],
              let opfData = unzip(url, opfPath)
        else { return ExtractedMetadata() }
        let base = opfPath.split(separator: "/").dropLast().joined(separator: "/")
        return opf(opfData, baseDir: base, coverLoader: cover ? { unzip(url, $0) } : nil)
    }

    private static func unzip(_ archive: URL, _ entry: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    private static func pdf(_ url: URL, cover: Bool) -> ExtractedMetadata {
        var m = ExtractedMetadata()
        guard let doc = PDFDocument(url: url) else { return m }
        let attrs = doc.documentAttributes ?? [:]
        m.title = attrs[PDFDocumentAttribute.titleAttribute] as? String
        m.author = attrs[PDFDocumentAttribute.authorAttribute] as? String
        if cover, let page = doc.page(at: 0) {
            m.cover = jpeg(page.thumbnail(of: NSSize(width: 600, height: 900), for: .mediaBox))
        }
        return m
    }
}
