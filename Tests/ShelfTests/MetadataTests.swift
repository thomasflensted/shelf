import Foundation
import Testing
@testable import Shelf

struct OPFTests {
    let opf = """
    <?xml version="1.0"?>
    <package xmlns="http://www.idpf.org/2007/opf" xmlns:opf="http://www.idpf.org/2007/opf">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>Guards! Guards!</dc:title>
        <dc:creator opf:role="aut">Terry Pratchett</dc:creator>
        <dc:creator opf:role="ill">Josh Kirby</dc:creator>
        <dc:identifier opf:scheme="ISBN">978-0-552-13890-1</dc:identifier>
        <dc:subject>Fantasy</dc:subject>
        <dc:description>&lt;p&gt;The &lt;b&gt;Watch&lt;/b&gt; takes on a dragon.&lt;/p&gt;</dc:description>
        <meta name="calibre:series" content="Discworld"/>
        <meta name="calibre:series_index" content="8.0"/>
        <meta name="cover" content="img1"/>
      </metadata>
      <manifest>
        <item id="img1" href="../Images/Cover%20Art.jpg" media-type="image/jpeg"/>
      </manifest>
    </package>
    """

    @Test func readsCalibreMetadata() {
        let meta = Metadata.opf(Data(opf.utf8))
        #expect(meta.title == "Guards! Guards!")
        #expect(meta.author == "Terry Pratchett")
        #expect(meta.isbn == "9780552138901")
        #expect(meta.tags == ["Fantasy"])
        #expect(meta.summary == "The Watch takes on a dragon.")
        #expect(meta.series == "Discworld")
        #expect(meta.seriesIndex == 8)
    }

    @Test func loadsCoverRelativeToPackage() {
        var requested: String?
        _ = Metadata.opf(Data(opf.utf8), baseDir: "OEBPS/Text") { requested = $0; return nil }
        #expect(requested == "OEBPS/Images/Cover Art.jpg")
    }

    @Test func coverHrefPrefersEpub3CoverImageProperty() throws {
        let xml = """
        <manifest>
          <item id="cover" href="old.jpg" media-type="image/jpeg"/>
          <item id="x" href="new.jpg" properties="cover-image" media-type="image/jpeg"/>
        </manifest>
        """
        let items = try #require(XMLTree.parse(Data(xml.utf8))).all("item")
        #expect(Metadata.coverHref(items: items, coverID: nil) == "new.jpg")
    }

    @Test func readsUrnISBN() {
        let xml = "<package><dc:identifier xmlns:dc=\"x\">urn:isbn:0306406152</dc:identifier></package>"
        #expect(Metadata.opf(Data(xml.utf8)).isbn == "0306406152")
    }
}

struct NameAndISBNTests {
    @Test func cleanISBNAcceptsOnlyValidLengths() {
        #expect(Metadata.cleanISBN("978-1-4711-0589-0") == "9781471105890")
        #expect(Metadata.cleanISBN("0-8044-2957-x") == "080442957X")
        #expect(Metadata.cleanISBN("12345") == nil)
    }

    @Test func flipNameTurnsFileAsIntoDisplayName() {
        #expect(Metadata.flipName("Bryson, Bill") == "Bill Bryson")
        #expect(Metadata.flipName("Bill Bryson") == "Bill Bryson")
    }
}

struct MobiTests {
    @Test func readsTitleAuthorISBNAndCover() {
        let bytes = MobiBuilder(fullName: "Short Name", exth: [
            (100, "Bryson, Bill"), (503, "A Short History of Nearly Everything"), (104, "978-0-7679-0818-4"),
        ], cover: [0xFF, 0xD8, 0x01, 0x02]).build()

        let meta = Mobi.parse(bytes, includeCover: true)

        #expect(meta.title == "A Short History of Nearly Everything")
        #expect(meta.author == "Bill Bryson")
        #expect(meta.isbn == "9780767908184")
        #expect(meta.cover == Data([0xFF, 0xD8, 0x01, 0x02]))
    }

    @Test func fallsBackToFullNameAndSkipsCoverWhenAsked() {
        let bytes = MobiBuilder(fullName: "Only Name", exth: [], cover: [1, 2, 3]).build()
        let meta = Mobi.parse(bytes, includeCover: false)
        #expect(meta.title == "Only Name")
        #expect(meta.cover == nil)
    }

    @Test func ignoresFilesThatAreNotMobi() {
        let meta = Mobi.parse(Array(repeating: 0x41, count: 300), includeCover: true)
        #expect(meta.title == nil)
    }
}

struct MobiBuilder {
    let fullName: String
    let exth: [(type: Int, value: String)]
    let cover: [UInt8]?

    private let mobiHeaderLength = 232

    func build() -> [UInt8] {
        let recordCount = cover == nil ? 1 : 2
        let rec0Start = 78 + recordCount * 8 + 2

        var exthBlock = Array("EXTH".utf8)
        var records: [UInt8] = []
        var coverEntry = cover == nil ? [] : [(201, be32(0))]
        for (type, value) in exth { coverEntry.append((type, Array(value.utf8))) }
        for (type, body) in coverEntry { records += be32(type) + be32(body.count + 8) + body }
        exthBlock += be32(12 + records.count) + be32(coverEntry.count) + records

        var rec0 = [UInt8](repeating: 0, count: 16 + mobiHeaderLength)
        put(Array("MOBI".utf8), at: 16, in: &rec0)
        put(be32(mobiHeaderLength), at: 20, in: &rec0)
        put(be32(65001), at: 28, in: &rec0)
        put(be32(16 + mobiHeaderLength + exthBlock.count), at: 84, in: &rec0)
        put(be32(fullName.utf8.count), at: 88, in: &rec0)
        put(be32(1), at: 108, in: &rec0)
        put(be32(0x40), at: 128, in: &rec0)
        rec0 += exthBlock + Array(fullName.utf8)

        var file = [UInt8](repeating: 0, count: 78)
        put(Array("BOOKMOBI".utf8), at: 60, in: &file)
        put(be16(recordCount), at: 76, in: &file)
        file += be32(rec0Start) + be32(0)
        if cover != nil { file += be32(rec0Start + rec0.count) + be32(0) }
        file += [0, 0] + rec0 + (cover ?? [])
        return file
    }

    private func be32(_ n: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8((n >> $0) & 0xFF) } }
    private func be16(_ n: Int) -> [UInt8] { [8, 0].map { UInt8((n >> $0) & 0xFF) } }
    private func put(_ bytes: [UInt8], at offset: Int, in buffer: inout [UInt8]) {
        buffer.replaceSubrange(offset ..< offset + bytes.count, with: bytes)
    }
}
