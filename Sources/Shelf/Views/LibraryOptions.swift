import Foundation

enum ViewMode: String {
    case grid, list
}

enum SortOption: String, CaseIterable, Identifiable {
    case added, title, author, series

    var id: Self { self }

    var label: String {
        switch self {
        case .added: "Recently Added"
        case .title: "Title"
        case .author: "Author"
        case .series: "Series"
        }
    }

    var comparators: [KeyPathComparator<Book>] {
        switch self {
        case .added: [KeyPathComparator(\Book.added, order: .reverse)]
        case .title: [KeyPathComparator(\Book.title)]
        case .author: [KeyPathComparator(\Book.authorSort), KeyPathComparator(\Book.title)]
        case .series: [KeyPathComparator(\Book.seriesSort), KeyPathComparator(\Book.title)]
        }
    }

    init(_ comparators: [KeyPathComparator<Book>]) {
        let keyPath = comparators.first?.keyPath
        self = SortOption.allCases.first { $0.comparators.first?.keyPath == keyPath } ?? .added
    }
}

enum GridSelection {
    static func click<ID: Hashable>(_ id: ID, in ordered: [ID], selection: Set<ID>, anchor: ID?,
                                    command: Bool, shift: Bool) -> (selection: Set<ID>, anchor: ID?) {
        if command {
            return (selection.symmetricDifference([id]), id)
        }
        if shift, let anchor, let from = ordered.firstIndex(of: anchor), let to = ordered.firstIndex(of: id) {
            return (Set(ordered[min(from, to)...max(from, to)]), anchor)
        }
        return ([id], id)
    }
}

enum RatingStars {
    static func symbols(for rating: Double) -> [String] {
        (0..<5).map { position in
            let star = Double(position)
            if star + 0.75 <= rating { return "star.fill" }
            if star + 0.25 <= rating { return "star.leadinghalf.filled" }
            return "star"
        }
    }
}
