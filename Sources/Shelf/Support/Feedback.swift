import Foundation
import Observation

@MainActor
@Observable
final class Feedback {
    private(set) var status: String?
    private(set) var isBusy = false
    var error: String?

    func progress(_ message: String) {
        status = message
        isBusy = true
    }

    func done(_ message: String) {
        status = message
        isBusy = false
        Task {
            try? await Task.sleep(for: .seconds(6))
            if status == message { status = nil }
        }
    }

    func fail(_ messages: [String]) {
        if !messages.isEmpty { error = messages.joined(separator: "\n") }
    }
}
