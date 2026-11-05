import SwiftUI

struct KindleView: View {
    @Environment(Kindle.self) private var kindle
    @Environment(Library.self) private var library
    @State private var selection = Set<KindleItem.ID>()
    @State private var sortOrder = [KeyPathComparator(\KindleItem.size, order: .reverse)]
    @State private var search = ""
    @State private var pendingRemove: [KindleItem] = []
    @State private var confirmCleanUp = false

    private var visible: [KindleItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let items = q.isEmpty ? kindle.items : kindle.items.filter { "\($0.title) \($0.author)".containsAllWords(of: q) }
        return items.sorted(using: sortOrder)
    }

    var body: some View {
        let inLibrary = MatchKeys(books: library.books)
        let inShelf: (KindleItem) -> Bool = inLibrary.contains
        let unbackedUp: (KindleItem) -> Bool = { $0.needsBackup(isInLibrary: inLibrary.contains($0)) }

        VStack(spacing: 0) {
            header
            Divider()
            Table(visible, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Title", value: \.title)
                TableColumn("Author", value: \.author)
                TableColumn("Format", value: \.format) { Text($0.format).foregroundStyle(.secondary) }
                    .width(min: 50, ideal: 60)
                TableColumn("Size", value: \.size) { Text($0.size.formatted(.byteCount(style: .file))).monospacedDigit() }
                    .width(min: 60, ideal: 80)
                TableColumn("Added", value: \.modified) { Text($0.modified, format: .dateTime.year().month().day()) }
                    .width(min: 80, ideal: 100)
                TableColumn("Source") { item in
                    if item.isPurchase {
                        Text("Amazon").foregroundStyle(.secondary).help("Bought from Amazon. Can be re-downloaded on the Kindle.")
                    } else if inShelf(item) {
                        Label("Shelf", systemImage: "checkmark").foregroundStyle(.green).help("Also in your Shelf library")
                    } else if !item.isClippings {
                        Text("Only here").foregroundStyle(.orange).help("Not in your Shelf library — copy it to Shelf before removing")
                    }
                }
                .width(min: 60, ideal: 80)
            }
            .contextMenu(forSelectionType: KindleItem.ID.self) { ids in
                let items = kindle.items.filter { ids.contains($0.id) }
                let missing = items.filter(unbackedUp)
                if !missing.isEmpty {
                    Button("Copy to Shelf") { library.importItems(missing.map(\.url)) }
                }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(items.map(\.url)) }
                Divider()
                Button("Remove from Kindle…", role: .destructive) { pendingRemove = items }
            } primaryAction: { ids in
                for item in kindle.items where ids.contains(item.id) { NSWorkspace.shared.open(item.url) }
            }
            .overlay {
                if kindle.scanning && kindle.items.isEmpty {
                    ProgressView("Reading \(kindle.name)…")
                } else if !kindle.scanning && kindle.items.isEmpty {
                    ContentUnavailableView("No Books on \(kindle.name)", systemImage: "book.closed",
                                           description: Text("Select books in your library and press ⌘K to send them."))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let status = kindle.status ?? library.importStatus {
                HStack { Text(status); Spacer() }
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).frame(height: 26).background(.bar)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search \(kindle.name)")
        .navigationTitle(kindle.name)
        .navigationSubtitle("\(kindle.items.count) books")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { kindle.rescan() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(kindle.scanning)
                Button { pendingRemove = kindle.items.filter { selection.contains($0.id) } } label: {
                    Label("Remove from Kindle", systemImage: "trash")
                }
                .keyboardShortcut(.delete)
                .disabled(selection.isEmpty)
                Button { kindle.eject() } label: { Label("Eject", systemImage: "eject") }
                    .keyboardShortcut("e")
                    .help("Eject \(kindle.name) (⌘E)")
            }
        }
        .confirmationDialog(removePrompt, isPresented: Binding(get: { !pendingRemove.isEmpty }, set: { if !$0 { pendingRemove = [] } })) {
            Button("Remove", role: .destructive) {
                kindle.remove(pendingRemove)
                selection = []
                pendingRemove = []
            }
        } message: {
            let notBackedUp = pendingRemove.filter(unbackedUp).count
            let purchases = pendingRemove.filter(\.isPurchase).count
            Text("This deletes the files and their reading position and highlights from the Kindle."
                 + (purchases > 0 ? " Amazon purchases can be downloaded again from the Kindle's library." : "")
                 + (notBackedUp > 0 ? " \(notBackedUp) of them aren't in your Shelf library. Copy them to Shelf first if you want to keep them." : ""))
        }
        .confirmationDialog("Remove \(kindle.orphans.count) leftover folders?", isPresented: $confirmCleanUp) {
            Button("Clean Up", role: .destructive) { kindle.cleanUp() }
        } message: {
            Text("These .sdr folders hold reading data for books that are no longer on the Kindle.")
        }
    }

    private var removePrompt: String {
        pendingRemove.count == 1 ? "Remove “\(pendingRemove[0].title)” from \(kindle.name)?" : "Remove \(pendingRemove.count) books from \(kindle.name)?"
    }

    private var header: some View {
        let used = max(kindle.totalBytes - kindle.freeBytes, 0)
        let fraction = kindle.totalBytes > 0 ? Double(used) / Double(kindle.totalBytes) : 0
        let level = StorageLevel(used: used, total: kindle.totalBytes)
        let fmt = { (bytes: Int64) in bytes.formatted(.byteCount(style: .file)) }
        let booksBytes = kindle.items.reduce(Int64(0)) { $0 + $1.size }

        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Storage").font(.headline)
                    Spacer()
                    Text("\(fmt(kindle.freeBytes)) free of \(fmt(kindle.totalBytes))")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                ProgressView(value: fraction)
                    .tint(level == .almostFull ? .red : level == .high ? .orange : .accentColor)
                Text("Books use \(fmt(booksBytes))" + (level == .almostFull ? " · Almost full, which slows the Kindle down. Remove large books you've finished." : ""))
                    .font(.caption).foregroundStyle(level == .almostFull ? .red : .secondary)
            }
            .frame(maxWidth: 520)

            Spacer()

            if !kindle.orphans.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Button("Clean Up…") { confirmCleanUp = true }
                    Text("\(kindle.orphans.count) leftover folders · \(fmt(kindle.orphanBytes))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
    }
}
