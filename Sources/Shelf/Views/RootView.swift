import SwiftUI

enum Source: Hashable { case library, kindle }

struct RootView: View {
    @Environment(Kindle.self) private var kindle
    @State private var source: Source = .library
    @State private var columns: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            List(selection: $source) {
                Label("Library", systemImage: "books.vertical").tag(Source.library)
                if kindle.connected {
                    Section("Devices") {
                        Label(kindle.name, systemImage: "book.closed")
                            .tag(Source.kindle)
                            .contextMenu { Button("Eject") { kindle.eject() } }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch source {
            case .library: LibraryView()
            case .kindle: KindleView()
            }
        }
        .onChange(of: kindle.connected, initial: true) { _, connected in
            withAnimation { columns = connected ? .all : .detailOnly }
            if !connected { source = .library }
        }
        .alert("Kindle", isPresented: Binding(get: { kindle.lastError != nil }, set: { if !$0 { kindle.lastError = nil } })) {
            Button("OK") { kindle.lastError = nil }
        } message: {
            Text(kindle.lastError ?? "")
        }
    }
}
