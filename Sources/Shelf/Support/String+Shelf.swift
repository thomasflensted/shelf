import Foundation

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    var safeFileName: String {
        var name = replacingOccurrences(of: "[/:\\\\?*\"<>|]", with: "_", options: .regularExpression).trimmed
        while name.hasPrefix(".") { name.removeFirst() }
        if name.count > 80 { name = String(name.prefix(80)).trimmed }
        return name.isEmpty ? "Untitled" : name
    }

    func containsAllWords(of query: String) -> Bool {
        query.split(separator: " ").allSatisfy { localizedCaseInsensitiveContains($0) }
    }
}

func counted(_ count: Int, _ singular: String) -> String {
    "\(count) \(singular)\(count == 1 ? "" : "s")"
}
