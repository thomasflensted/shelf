import Foundation

enum Mobi {
    private static let headerReadLimit = 512 * 1024
    private static let noCover = 0xFFFF_FFFF
    private static let hasEXTHFlag = 0x40

    private enum EXTH {
        static let author = 100
        static let description = 103
        static let isbn = 104
        static let subject = 105
        static let coverOffset = 201
        static let thumbnailOffset = 202
        static let updatedTitle = 503
    }

    static func read(_ url: URL, cover: Bool) -> ExtractedMetadata {
        // Everything but the cover image sits in the first record, so scans skip reading whole files.
        let data = cover ? try? Data(contentsOf: url, options: .mappedIfSafe) : prefix(of: url)
        return data.map { parse([UInt8]($0), includeCover: cover) } ?? ExtractedMetadata()
    }

    static func parse(_ bytes: [UInt8], includeCover: Bool) -> ExtractedMetadata {
        let r = ByteReader(bytes: bytes)
        guard let offsets = recordOffsets(r), let rec0 = offsets.first,
              r.ascii(rec0 + 16, 4) == "MOBI", let headerLength = r.u32(rec0 + 20)
        else { return ExtractedMetadata() }
        let encoding: String.Encoding = r.u32(rec0 + 28) == 65001 ? .utf8 : .windowsCP1252
        func text(_ range: Range<Int>) -> String? { r.string(range, encoding: encoding) }

        var m = ExtractedMetadata()
        if let offset = r.u32(rec0 + 84), let length = r.u32(rec0 + 88) {
            m.title = text(rec0 + offset ..< rec0 + offset + length)
        }
        var authors: [String] = []
        var coverIndex: Int?
        for (type, body) in exthRecords(r, at: rec0 + 16 + headerLength, flags: r.u32(rec0 + 128) ?? 0) {
            switch type {
            case EXTH.author: text(body).map { authors.append(Metadata.flipName($0)) }
            case EXTH.updatedTitle: if let t = text(body)?.nonEmpty { m.title = t }
            case EXTH.description: m.summary = text(body)?.strippingHTML
            case EXTH.isbn: m.isbn = text(body).flatMap(Metadata.cleanISBN) ?? m.isbn
            case EXTH.subject: text(body).map { m.tags.append($0) }
            case EXTH.coverOffset: coverIndex = r.u32(body.lowerBound)
            case EXTH.thumbnailOffset: coverIndex = coverIndex ?? r.u32(body.lowerBound)
            default: break
            }
        }
        m.author = authors.joined(separator: " & ")
        if includeCover, let coverIndex, coverIndex != noCover {
            m.cover = imageRecord(r, offsets: offsets, index: (r.u32(rec0 + 108) ?? 0) + coverIndex)
        }
        return m
    }

    private static func prefix(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: headerReadLimit)
    }

    private static func recordOffsets(_ r: ByteReader) -> [Int]? {
        guard let count = r.u16(76), count > 0 else { return nil }
        let offsets = (0..<count).compactMap { r.u32(78 + $0 * 8) }
        return offsets.count == count ? offsets : nil
    }

    private static func exthRecords(_ r: ByteReader, at start: Int, flags: Int) -> [(type: Int, body: Range<Int>)] {
        guard flags & hasEXTHFlag != 0, r.ascii(start, 4) == "EXTH", let count = r.u32(start + 8) else { return [] }
        var records: [(Int, Range<Int>)] = []
        var position = start + 12
        for _ in 0..<count {
            guard let type = r.u32(position), let length = r.u32(position + 4), length >= 8 else { break }
            records.append((type, position + 8 ..< position + length))
            position += length
        }
        return records
    }

    private static func imageRecord(_ r: ByteReader, offsets: [Int], index: Int) -> Data? {
        guard index < offsets.count else { return nil }
        let end = index + 1 < offsets.count ? offsets[index + 1] : r.bytes.count
        return r.data(offsets[index] ..< end)
    }
}

struct ByteReader {
    let bytes: [UInt8]

    func u16(_ offset: Int) -> Int? {
        guard contains(offset ..< offset + 2) else { return nil }
        return Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    func u32(_ offset: Int) -> Int? {
        guard contains(offset ..< offset + 4) else { return nil }
        return (0..<4).reduce(0) { $0 << 8 | Int(bytes[offset + $1]) }
    }

    func ascii(_ offset: Int, _ length: Int) -> String? {
        guard contains(offset ..< offset + length) else { return nil }
        return String(bytes: bytes[offset ..< offset + length], encoding: .ascii)
    }

    func string(_ range: Range<Int>, encoding: String.Encoding) -> String? {
        guard !range.isEmpty, contains(range) else { return nil }
        return String(bytes: bytes[range], encoding: encoding) ?? String(bytes: bytes[range], encoding: .windowsCP1252)
    }

    func data(_ range: Range<Int>) -> Data? {
        guard !range.isEmpty, contains(range) else { return nil }
        return Data(bytes[range])
    }

    private func contains(_ range: Range<Int>) -> Bool { range.lowerBound >= 0 && range.upperBound <= bytes.count }
}
