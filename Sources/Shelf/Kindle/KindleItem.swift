import Foundation

/// A book file found on the Kindle.
struct KindleItem: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let title: String
    let author: String
    let size: Int64
    let modified: Date
    /// `.sdr` folders belonging to this book (reading position, highlights, and for Amazon books part of the book itself).
    let sidecars: [URL]
    let dedupeKey: String
    /// Bought from Amazon (DRM-protected; can be re-downloaded from the Kindle, can't be read in Shelf).
    let isPurchase: Bool

    var format: String { url.pathExtension.uppercased() }
    var stem: String { url.deletingPathExtension().lastPathComponent }
}
