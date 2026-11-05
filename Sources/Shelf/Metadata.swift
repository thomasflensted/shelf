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

    /// Fill gaps in self with values from other.
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
    /// `cover: false` skips cover extraction and only reads the start of MOBI files (fast, for scanning a Kindle).
    static func extract(from url: URL, cover: Bool = true) -> ExtractedMetadata {
        var meta: ExtractedMetadata
        switch url.pathExtension.lowercased() {
        case "epub": meta = epub(url, cover: cover)
        case "mobi", "azw", "azw3", "prc": meta = mobi(url, cover: cover)
        case "pdf": meta = pdf(url, cover: cover)
        default: meta = ExtractedMetadata()
        }
        if meta.title?.trimmingCharacters(in: .whitespaces).isEmpty ?? true {
            meta.title = url.deletingPathExtension().lastPathComponent
        }
        return meta
    }

    // MARK: OPF (EPUB package files and Calibre's metadata.opf)

    static func opf(_ data: Data, baseDir: String = "", coverLoader: ((String) -> Data?)? = nil) -> ExtractedMetadata {
        guard let root = XMLTree.parse(data) else { return ExtractedMetadata() }
        var m = ExtractedMetadata()
        m.title = root.first("title")?.text
        let creators = root.all("creator")
        let authors = creators.filter { ($0.attrs["role"] ?? "aut") == "aut" }.map(\.text).filter { !$0.isEmpty }
        m.author = (authors.isEmpty ? creators.map(\.text) : authors).joined(separator: " & ")
        m.isbn = root.all("identifier").lazy.compactMap { id -> String? in
            let scheme = (id.attrs["scheme"] ?? "").lowercased()
            let text = id.text.lowercased().replacingOccurrences(of: "urn:isbn:", with: "")
            guard scheme == "isbn" || id.text.lowercased().hasPrefix("urn:isbn:") else { return nil }
            return Metadata.cleanISBN(text)
        }.first
        m.tags = root.all("subject").map(\.text).filter { !$0.isEmpty }
        if let d = root.first("description")?.text, !d.isEmpty { m.summary = stripHTML(d) }

        var coverID: String?
        for meta in root.all("meta") {
            switch meta.attrs["name"] {
            case "calibre:series": m.series = meta.attrs["content"]
            case "calibre:series_index": m.seriesIndex = meta.attrs["content"].flatMap(Double.init)
            case "cover": coverID = meta.attrs["content"]
            default: break
            }
        }

        if let coverLoader {
            let items = root.all("item")
            let item = items.first { ($0.attrs["properties"] ?? "").contains("cover-image") }
                ?? items.first { $0.attrs["id"] == coverID && coverID != nil }
                ?? items.first { ($0.attrs["id"] ?? "").lowercased().contains("cover") && ($0.attrs["media-type"] ?? "").hasPrefix("image/") }
            if let href = item?.attrs["href"]?.removingPercentEncoding {
                m.cover = coverLoader(resolve(href, against: baseDir))
            }
        }
        return m
    }

    private static func resolve(_ href: String, against base: String) -> String {
        var parts = base.split(separator: "/").map(String.init)
        for p in href.split(separator: "/") {
            if p == ".." { _ = parts.popLast() } else if p != "." { parts.append(String(p)) }
        }
        return parts.joined(separator: "/")
    }

    private static func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: EPUB

    static func epub(_ url: URL, cover: Bool = true) -> ExtractedMetadata {
        guard let container = unzip(url, "META-INF/container.xml"),
              let tree = XMLTree.parse(container),
              let opfPath = tree.first("rootfile")?.attrs["full-path"],
              let opfData = unzip(url, opfPath)
        else { return ExtractedMetadata() }
        let base = (opfPath as NSString).deletingLastPathComponent
        return opf(opfData, baseDir: base, coverLoader: cover ? { unzip(url, $0) } : nil)
    }

    private static func unzip(_ archive: URL, _ entry: String) -> Data? {
        // unzip treats entry names as patterns; escape wildcard characters.
        var escaped = ""
        for c in entry {
            if "[]*?\\".contains(c) { escaped.append("\\") }
            escaped.append(c)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", archive.path, escaped]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    // MARK: MOBI / AZW / AZW3

    static func mobi(_ url: URL, cover: Bool = true) -> ExtractedMetadata {
        let data: Data?
        if cover {
            data = try? Data(contentsOf: url, options: .mappedIfSafe)
        } else {
            // Header, record 0 and EXTH sit at the start of the file.
            let h = try? FileHandle(forReadingFrom: url)
            data = try? h?.read(upToCount: 512 * 1024)
            try? h?.close()
        }
        guard let data else { return ExtractedMetadata() }
        let b = [UInt8](data)
        func u32(_ o: Int) -> Int? {
            guard o >= 0, o + 4 <= b.count else { return nil }
            return Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
        }
        func u16(_ o: Int) -> Int? {
            guard o >= 0, o + 2 <= b.count else { return nil }
            return Int(b[o]) << 8 | Int(b[o + 1])
        }
        func ascii(_ o: Int, _ n: Int) -> String? {
            guard o >= 0, o + n <= b.count else { return nil }
            return String(bytes: b[o..<o + n], encoding: .ascii)
        }

        var m = ExtractedMetadata()
        guard let count = u16(76), count > 0 else { return m }
        let offsets = (0..<count).compactMap { u32(78 + $0 * 8) }
        guard offsets.count == count, let rec0 = offsets.first,
              ascii(rec0 + 16, 4) == "MOBI",
              let headerLen = u32(rec0 + 20) else { return m }
        let encoding: String.Encoding = u32(rec0 + 28) == 65001 ? .utf8 : .windowsCP1252
        func string(_ o: Int, _ n: Int) -> String? {
            guard o >= 0, n > 0, o + n <= b.count else { return nil }
            return String(bytes: b[o..<o + n], encoding: encoding) ?? String(bytes: b[o..<o + n], encoding: .windowsCP1252)
        }

        if let off = u32(rec0 + 84), let len = u32(rec0 + 88) { m.title = string(rec0 + off, len) }
        let firstImage = u32(rec0 + 108) ?? 0

        var authors: [String] = []
        var coverOffset: Int?
        var thumbOffset: Int?
        if let flags = u32(rec0 + 128), flags & 0x40 != 0 {
            let exth = rec0 + 16 + headerLen
            if ascii(exth, 4) == "EXTH", let n = u32(exth + 8) {
                var p = exth + 12
                for _ in 0..<n {
                    guard let type = u32(p), let len = u32(p + 4), len >= 8 else { break }
                    let body = p + 8, size = len - 8
                    switch type {
                    case 100: string(body, size).map { authors.append($0) }
                    case 503: if let t = string(body, size), !t.isEmpty { m.title = t }
                    case 103: m.summary = string(body, size).map(stripHTML)
                    case 105: string(body, size).map { m.tags.append($0) }
                    case 104: if let i = string(body, size).flatMap(cleanISBN) { m.isbn = i }
                    case 201: coverOffset = u32(body)
                    case 202: thumbOffset = u32(body)
                    default: break
                    }
                    p += len
                }
            }
        }
        m.author = authors.map(flipName).joined(separator: " & ")

        if cover, let rel = coverOffset ?? thumbOffset, rel != 0xFFFFFFFF {
            let idx = firstImage + rel
            if idx < offsets.count {
                let start = offsets[idx]
                let end = idx + 1 < offsets.count ? offsets[idx + 1] : b.count
                if start < end, end <= b.count { m.cover = Data(b[start..<end]) }
            }
        }
        return m
    }

    /// Digits (and a trailing X) of a valid-length ISBN, else nil.
    static func cleanISBN(_ s: String) -> String? {
        let digits = s.uppercased().filter { $0.isNumber || $0 == "X" }
        return digits.count == 10 || digits.count == 13 ? digits : nil
    }

    /// "Bryson, Bill" → "Bill Bryson". Leaves anything more complex alone.
    static func flipName(_ name: String) -> String {
        let parts = name.components(separatedBy: ", ")
        guard parts.count == 2, !parts[0].contains(" & "), !parts[1].contains(" & "),
              parts[1].split(separator: " ").count <= 3 else { return name }
        return "\(parts[1]) \(parts[0])"
    }

    // MARK: PDF

    static func pdf(_ url: URL, cover: Bool = true) -> ExtractedMetadata {
        var m = ExtractedMetadata()
        guard let doc = PDFDocument(url: url) else { return m }
        let attrs = doc.documentAttributes ?? [:]
        m.title = attrs[PDFDocumentAttribute.titleAttribute] as? String
        m.author = attrs[PDFDocumentAttribute.authorAttribute] as? String
        if cover, let page = doc.page(at: 0) {
            let thumb = page.thumbnail(of: NSSize(width: 600, height: 900), for: .mediaBox)
            m.cover = jpeg(thumb)
        }
        return m
    }

    static func jpeg(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}

// MARK: - Tiny XML tree

final class XMLTree {
    let name: String
    var attrs: [String: String] = [:]
    var text = ""
    var children: [XMLTree] = []

    init(name: String) { self.name = name }

    static func parse(_ data: Data) -> XMLTree? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.parse()
        return builder.root
    }

    func all(_ local: String) -> [XMLTree] {
        children.flatMap { ($0.name == local ? [$0] : []) + $0.all(local) }
    }

    func first(_ local: String) -> XMLTree? { all(local).first }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLTree?
        var stack: [XMLTree] = []

        static func local(_ s: String) -> String { s.split(separator: ":").last.map(String.init) ?? s }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let node = XMLTree(name: Builder.local(elementName))
            for (k, v) in attributeDict {
                node.attrs[k] = v
                node.attrs[Builder.local(k)] = v
            }
            if let parent = stack.last { parent.children.append(node) } else { root = node }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if let node = stack.popLast() {
                node.text = node.text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }
}
