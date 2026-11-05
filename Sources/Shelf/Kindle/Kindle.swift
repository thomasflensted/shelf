import AppKit
import Foundation
import Observation

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
    let feedback = Feedback()

    private var onDevice = MatchKeys(items: [])

    var connected: Bool { volume != nil }
    var name: String { volume?.lastPathComponent ?? "Kindle" }
    private var documents: URL? { volume?.appendingPathComponent("documents", isDirectory: true) }

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.detect() }
            }
        }
        detect()
    }

    static func isKindle(_ volume: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: volume.appendingPathComponent("documents").path)
            && fm.fileExists(atPath: volume.appendingPathComponent("system").path)
    }

    func detect() {
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        let found = volumes.first(where: Kindle.isKindle)
        guard found != volume else { return }
        volume = found
        apply(KindleScanner.Result())
        if found != nil { rescan() }
    }

    func eject() {
        guard let volume else { return }
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
            self.volume = nil
            apply(KindleScanner.Result())
        } catch {
            feedback.fail(["Couldn't eject: \(error.localizedDescription)"])
        }
    }

    func rescan() {
        guard let documents, let volume else { return }
        scanning = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { KindleScanner.scan(documents) }.value
            guard self.volume == volume else { return }
            apply(result)
            refreshStorage()
            scanning = false
        }
    }

    func contains(_ book: Book) -> Bool { connected && onDevice.contains(book) }

    func items(for book: Book) -> [KindleItem] {
        let keys = MatchKeys(books: [book])
        return items.filter(keys.contains)
    }

    func send(_ books: [Book], from library: Library) {
        guard let documents else { return }
        let skipped = books.filter { Formats.best(of: $0.files, in: Formats.kindleOrder) == nil }.map(\.title)
        let jobs = books.compactMap { book -> (from: URL, to: URL)? in
            guard let file = Formats.best(of: book.files, in: Formats.kindleOrder) else { return nil }
            let name = KindleFiles.fileStem(for: book) + "." + Formats.ext(file)
            return (library.fileURL(book, file), documents.appendingPathComponent(name))
        }
        guard !jobs.isEmpty else {
            feedback.fail(["No Kindle-compatible format (AZW3, MOBI, PDF…) for: " + skipped.joined(separator: ", ")])
            return
        }
        feedback.progress("Sending \(counted(jobs.count, "book"))…")
        Task {
            let failures = await Task.detached(priority: .userInitiated) { Kindle.copy(jobs) }.value
            feedback.done("Sent \(counted(jobs.count - failures.count, "book")) to \(name)")
            feedback.fail(failures + (skipped.isEmpty ? [] : ["No Kindle-compatible format for: " + skipped.joined(separator: ", ")]))
            rescan()
        }
    }

    func remove(_ remove: [KindleItem]) {
        let fm = FileManager.default
        var failures: [String] = []
        for item in remove {
            do {
                try fm.removeItem(at: item.url)
                for sdr in item.sidecars { try? fm.removeItem(at: sdr) }
            } catch {
                failures.append("\(item.title): \(error.localizedDescription)")
            }
        }
        feedback.done("Removed \(counted(remove.count - failures.count, "book")) from \(name)")
        feedback.fail(failures)
        rescan()
    }

    func cleanUp() {
        let count = orphans.count, bytes = orphanBytes
        for sdr in orphans { try? FileManager.default.removeItem(at: sdr) }
        feedback.done("Removed \(counted(count, "leftover folder")), freed \(bytes.formatted(.byteCount(style: .file)))")
        rescan()
    }

    private nonisolated static func copy(_ jobs: [(from: URL, to: URL)]) -> [String] {
        let fm = FileManager.default
        return jobs.compactMap { job in
            do {
                if fm.fileExists(atPath: job.to.path) { try fm.removeItem(at: job.to) }
                try fm.copyItem(at: job.from, to: job.to)
                return nil
            } catch {
                return "\(job.to.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private func apply(_ result: KindleScanner.Result) {
        items = result.items
        orphans = result.orphans
        orphanBytes = result.orphanBytes
        onDevice = MatchKeys(items: result.items)
    }

    private func refreshStorage() {
        guard let values = try? volume?.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        else { return }
        totalBytes = Int64(values.volumeTotalCapacity ?? 0)
        freeBytes = Int64(values.volumeAvailableCapacity ?? 0)
    }
}
