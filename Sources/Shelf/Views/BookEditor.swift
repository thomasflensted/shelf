import SwiftUI

struct BookEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let book: Book
    @State private var title: String
    @State private var author: String
    @State private var summary: String
    @State private var newCover: URL?
    @State private var newCoverImage: NSImage?

    init(book: Book) {
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _summary = State(initialValue: book.summary ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 24) {
                cover
                fields
            }
            .padding(20)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 640)
    }

    private var cover: some View {
        VStack(spacing: 8) {
            Group {
                if let newCoverImage {
                    Image(nsImage: newCoverImage).resizable().aspectRatio(contentMode: .fill)
                } else {
                    CoverView(book: book, coverURL: library.coverURL(book))
                }
            }
            .frame(width: 160, height: 240)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(radius: 3, y: 2)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return useCover(url)
            }
            Button("Change Cover…", action: pickCover).controlSize(.small)
            Text("or drop an image").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var fields: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 12) {
            GridRow {
                label("Title")
                TextField("Title", text: $title, prompt: Text("Title"))
            }
            GridRow {
                label("Author")
                TextField("Author", text: $author, prompt: Text("Separate authors with &"))
            }
            GridRow {
                label("Description")
                TextField("Description", text: $summary, axis: .vertical)
                    .lineLimit(8...12)
            }
            GridRow {
                label("Files")
                HStack {
                    Text(book.formats).foregroundStyle(.secondary)
                    Button { library.reveal([book]) } label: { Image(systemName: "folder") }
                        .controlSize(.small)
                        .help("Show in Finder")
                }
            }
        }
        .textFieldStyle(.roundedBorder)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func label(_ text: String) -> some View {
        Text(text).gridColumnAlignment(.trailing)
    }

    private func pickCover() {
        guard let url = Panels.chooseImage() else { return }
        _ = useCover(url)
    }

    private func useCover(_ url: URL) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        newCover = url
        newCoverImage = image
        return true
    }

    private func save() {
        var edited = book
        edited.title = title.trimmed.nonEmpty ?? book.title
        edited.author = author.trimmed.nonEmpty ?? Book.unknownAuthor
        edited.summary = summary.trimmed.nonEmpty
        library.update(edited, newCover: newCover)
        dismiss()
    }
}
