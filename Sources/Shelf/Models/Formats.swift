import Foundation

enum Formats {
    static let all: Set<String> = ["epub", "pdf", "mobi", "azw", "azw3", "kfx", "cbz", "cbr", "fb2", "djvu", "txt", "rtf", "docx", "lit", "prc"]
    static let readingOrder = ["epub", "azw3", "mobi", "azw", "pdf", "cbz", "cbr", "fb2", "djvu", "txt", "rtf"]
    static let kindleOrder = ["azw3", "mobi", "azw", "kfx", "pdf", "txt"]

    static func ext(_ fileName: String) -> String { URL(filePath: fileName, directoryHint: .notDirectory).pathExtension.lowercased() }

    static func isBook(_ fileName: String) -> Bool { all.contains(ext(fileName)) }

    static func sorted(_ fileNames: [String], by order: [String]) -> [String] {
        sorted(fileNames, by: order, name: { $0 })
    }

    static func sorted<T>(_ items: [T], by order: [String], name: (T) -> String) -> [T] {
        items.sorted { rank(ext(name($0)), in: order) < rank(ext(name($1)), in: order) }
    }

    static func best(of fileNames: [String], in order: [String]) -> String? {
        sorted(fileNames.filter { order.contains(ext($0)) }, by: order).first
    }

    private static func rank(_ ext: String, in order: [String]) -> Int { order.firstIndex(of: ext) ?? order.count }
}
