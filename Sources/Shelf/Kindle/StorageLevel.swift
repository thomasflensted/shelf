enum StorageLevel {
    case normal, high, almostFull

    init(used: Int64, total: Int64) {
        let fraction = total > 0 ? Double(used) / Double(total) : 0
        switch fraction {
        case 0.9...: self = .almostFull
        case 0.75...: self = .high
        default: self = .normal
        }
    }
}
