import Foundation

struct KindleItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let title: String
    let author: String
    let size: Int64
    let modified: Date
    let sidecars: [URL]
    let dedupeKey: String
    let isPurchase: Bool

    var format: String { url.pathExtension.uppercased() }
    var stem: String { url.deletingPathExtension().lastPathComponent }
    var isClippings: Bool { format == "TXT" }

    func needsBackup(isInLibrary: Bool) -> Bool { !isPurchase && !isInLibrary && !isClippings }
}
