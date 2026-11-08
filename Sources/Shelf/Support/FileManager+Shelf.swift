import Foundation

extension FileManager {
    func contentsRecursively(of folder: URL, descendingInto shouldDescend: (URL) -> Bool = { _ in true }) -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let children = (try? contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return children.flatMap { child in
            child.isDirectory && shouldDescend(child)
                ? [child] + contentsRecursively(of: child, descendingInto: shouldDescend)
                : [child]
        }
    }
}

extension URL {
    var isDirectory: Bool { (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    var fileSize: Int64 { Int64((try? resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
}
