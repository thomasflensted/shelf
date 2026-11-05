import AppKit
import Foundation
import Observation

/// Watches for a USB-mounted Kindle and manages the books on it.
@MainActor
@Observable
final class Kindle {
    private(set) var volume: URL?
    private(set) var items: [KindleItem] = []
    private(set) var orphans: [URL] = []
    private(set) var orphanBytes: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var freeBytes: Int64 = 0
    private(set) var scanning = false
    var status: String?
    var lastError: String?

    private var keys: Set<String> = []
    private var stems: Set<String> = []

    var connected: Bool { volume != nil }
    var name: String { volume?.lastPathComponent ?? "Kindle" }
    private var documents: URL? { volume?.appendingPathComponent("documents", isDirectory: true) }

    init() {
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.detect() }
            }
        }
        detect()
    }

    // MARK: Detection

    func detect() {
        let fm = FileManager.default
        let volumes = fm.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let found = volumes.first { v in
            fm.fileExists(atPath: v.appendingPathComponent("documents").path)
                && fm.fileExists(atPath: v.appendingPathComponent("system").path)
        }
        guard found != volume else { return }
        volume = found
        items = []; orphans = []; keys = []; stems = []
        if found != nil { rescan() }
    }

    func eject() {
        guard let volume else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            self.volume = nil
            items = []; orphans = []; keys = []; stems = []
        } catch {
            lastError = "Couldn't eject: \(error.localizedDescription)"
        }
    }

    // MARK: Scanning

    func rescan() {
        guard let documents, let volume else { return }
        scanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { Kindle.scan(documents) }.value
            guard self.volume == volume else { return }
            items = result.items
            orphans = result.orphans
            orphanBytes = result.orphanBytes
            keys = Set(items.map(\.dedupeKey))
            stems = Set(items.map { $0.stem.lowercased() })
            refreshStorage()
            scanning = false
        }
    }

    private func refreshStorage() {
        guard let volume,
              let v = try? volume.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        else { return }
        totalBytes = Int64(v.volumeTotalCapacity ?? 0)
        freeBytes = Int64(v.volumeAvailableCapacity ?? 0)
    }

    /// The Amazon ID at the end of a file name: "Title_B079L5DDB4" or "Title_B079L5DDB4_sample".
    nonisolated static func asin(_ stem: String) -> String? {
        guard let m = stem.range(of: "_([A-Z0-9]{10})(_sample)?$", options: .regularExpression) else { return nil }
        let id = stem[m].split(separator: "_").first.map(String.init) ?? ""
        return id.contains(where: \.isNumber) ? id : nil
    }

    /// "Pragmatic Programmer, The_ Your journey…_B07VRS84D1" → "The Pragmatic Programmer: Your journey…"
    nonisolated static func prettyTitle(_ stem: String) -> String {
        var t = stem
        let sample = t.hasSuffix("_sample")
        if let m = t.range(of: "_([A-Z0-9]{10})(_sample)?$", options: .regularExpression) { t.removeSubrange(m) }
        t = t.replacingOccurrences(of: "_ ", with: ": ").replacingOccurrences(of: "_", with: " ")
        var head = t, tail = ""
        if let cut = [t.range(of: ": "), t.range(of: " (")].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) {
            head = String(t[..<cut.lowerBound]); tail = String(t[cut.lowerBound...])
        }
        for article in ["The", "A", "An"] where head.hasSuffix(", \(article)") {
            head = article + " " + head.dropLast(article.count + 2)
        }
        return head + tail + (sample ? " (sample)" : "")
    }

    nonisolated static func scan(_ documents: URL) -> (items: [KindleItem], orphans: [URL], orphanBytes: Int64) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        var books: [(url: URL, size: Int64, modified: Date)] = []
        var sdrs: [URL] = []
        var stemsByDir: [URL: Set<String>] = [:]
        var asinsByDir: [URL: Set<String>] = [:]

        let e = fm.enumerator(at: documents, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        while let url = e?.nextObject() as? URL {
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                if url.pathExtension.lowercased() == "sdr" { sdrs.append(url); e?.skipDescendants() }
                continue
            }
            guard Formats.isBook(url.lastPathComponent) else { continue }
            let dir = url.deletingLastPathComponent(), stem = url.deletingPathExtension().lastPathComponent
            stemsByDir[dir, default: []].insert(stem)
            if let id = asin(stem) { asinsByDir[dir, default: []].insert(id) }
            books.append((url, Int64(v?.fileSize ?? 0), v?.contentModificationDate ?? .distantPast))
        }

        // The Kindle often keeps a second, short-named .sdr per Amazon book ("Title_ASIN.sdr"), so match on ASIN too.
        func belongs(_ sdr: URL, stem: String, asin id: String?) -> Bool {
            let s = sdr.deletingPathExtension().lastPathComponent
            return s == stem || (id != nil && asin(s) == id)
        }

        let purchasesDir = documents.appendingPathComponent("Downloads").path + "/"
        let items = books.map { b -> KindleItem in
            let dir = b.url.deletingLastPathComponent(), stem = b.url.deletingPathExtension().lastPathComponent
            let id = asin(stem)
            let meta = Metadata.extract(from: b.url, cover: false)
            let fromFile = meta.title.flatMap { $0 == stem ? nil : $0 }
            let title = fromFile ?? prettyTitle(stem)
            let author = meta.author?.nonEmpty ?? ""
            return KindleItem(
                url: b.url, title: title, author: author, size: b.size, modified: b.modified,
                sidecars: sdrs.filter { $0.deletingLastPathComponent() == dir && belongs($0, stem: stem, asin: id) },
                dedupeKey: Book.dedupeKey(title: title, author: author),
                isPurchase: id != nil && b.url.path.hasPrefix(purchasesDir))
        }

        // A .sdr folder with no book file of the same name or Amazon ID is leftover junk.
        let orphans = sdrs.filter { sdr in
            let dir = sdr.deletingLastPathComponent(), stem = sdr.deletingPathExtension().lastPathComponent
            if stemsByDir[dir]?.contains(stem) == true { return false }
            if let id = asin(stem), asinsByDir[dir]?.contains(id) == true { return false }
            return true
        }
        let orphanBytes = orphans.reduce(Int64(0)) { $0 + folderSize($1) }
        return (items, orphans, orphanBytes)
    }

    nonisolated private static func folderSize(_ url: URL) -> Int64 {
        var total: Int64 = 0
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        while let f = e?.nextObject() as? URL {
            total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    // MARK: Matching library books

    private static func sendName(_ b: Book) -> String { "\(b.title) - \(b.author)".safeFileName }

    func contains(_ book: Book) -> Bool {
        connected && (keys.contains(book.dedupeKey) || stems.contains(Kindle.sendName(book).lowercased()))
    }

    func items(for book: Book) -> [KindleItem] {
        let stem = Kindle.sendName(book).lowercased()
        return items.filter { $0.dedupeKey == book.dedupeKey || $0.stem.lowercased() == stem }
    }

    // MARK: Changing the device

    static let sendOrder = ["azw3", "mobi", "azw", "kfx", "pdf", "txt"]

    func send(_ books: [Book], from library: Library) {
        guard let documents else { lastError = "No Kindle connected."; return }
        var jobs: [(URL, URL)] = []
        var skipped: [String] = []
        for b in books {
            let file = b.files
                .compactMap { f in Kindle.sendOrder.firstIndex(of: (f as NSString).pathExtension.lowercased()).map { (f, $0) } }
                .min { $0.1 < $1.1 }?.0
            guard let file else { skipped.append(b.title); continue }
            let dest = documents.appendingPathComponent(Kindle.sendName(b) + "." + (file as NSString).pathExtension.lowercased())
            jobs.append((library.fileURL(b, file), dest))
        }
        guard !jobs.isEmpty else {
            lastError = "No Kindle-compatible format (AZW3, MOBI, PDF…) for: " + skipped.joined(separator: ", ")
            return
        }
        status = "Sending \(jobs.count) book\(jobs.count == 1 ? "" : "s")…"
        Task {
            let failures = await Task.detached(priority: .userInitiated) { () -> [String] in
                var failures: [String] = []
                let fm = FileManager.default
                for (src, dest) in jobs {
                    do {
                        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
                        try fm.copyItem(at: src, to: dest)
                    } catch { failures.append("\(dest.lastPathComponent): \(error.localizedDescription)") }
                }
                return failures
            }.value
            let sent = jobs.count - failures.count
            status = "Sent \(sent) book\(sent == 1 ? "" : "s") to \(name)"
            var problems = failures
            if !skipped.isEmpty { problems.append("No Kindle-compatible format for: " + skipped.joined(separator: ", ")) }
            if !problems.isEmpty { lastError = problems.joined(separator: "\n") }
            clearStatusSoon()
            rescan()
        }
    }

    /// Deletes the book files and their .sdr folders. Note: this also removes reading position and highlights.
    func remove(_ remove: [KindleItem]) {
        let fm = FileManager.default
        var failures: [String] = []
        for item in remove {
            do {
                try fm.removeItem(at: item.url)
                for sdr in item.sidecars { try? fm.removeItem(at: sdr) }
            } catch { failures.append("\(item.title): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { lastError = failures.joined(separator: "\n") }
        status = "Removed \(remove.count - failures.count) book\(remove.count - failures.count == 1 ? "" : "s") from \(name)"
        clearStatusSoon()
        rescan()
    }

    func cleanUp() {
        let fm = FileManager.default
        let count = orphans.count, bytes = orphanBytes
        for sdr in orphans { try? fm.removeItem(at: sdr) }
        status = "Removed \(count) leftover folder\(count == 1 ? "" : "s"), freed \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        clearStatusSoon()
        rescan()
    }

    private func clearStatusSoon() {
        let current = status
        Task {
            try? await Task.sleep(for: .seconds(6))
            if status == current { status = nil }
        }
    }
}
