import SwiftUI

extension Binding where Value == Bool {
    init<C: RangeReplaceableCollection>(isNotEmpty collection: Binding<C>) {
        self.init(get: { !collection.wrappedValue.isEmpty }, set: { if !$0 { collection.wrappedValue = C() } })
    }
}

extension View {
    func errorAlert(_ title: String, _ feedback: Feedback) -> some View {
        alert(title, isPresented: Binding(get: { feedback.error != nil }, set: { if !$0 { feedback.error = nil } })) {
            Button("OK") { feedback.error = nil }
        } message: {
            Text(feedback.error ?? "")
        }
    }
}

struct StatusBar: View {
    let message: String?
    let busy: Bool

    var body: some View {
        if let message {
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(message)
                Spacer()
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(.bar)
        }
    }
}
