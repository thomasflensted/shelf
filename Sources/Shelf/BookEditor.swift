import SwiftUI
import UniformTypeIdentifiers

struct BookEditor: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss

    let book: Book
    @State private var title: String
    @State private var author: String
    @State private var series: String
    @State private var seriesIndex: String
    @State private var tags: String
    @State private var summary: String
    @State private var newCover: URL?
    @State private var newCoverImage: NSImage?

    init(book: Book) {
        self.book = book
        _title = State(initialValue: book.title)
        _author = State(initialValue: book.author)
        _series = State(initialValue: book.series ?? "")
        _seriesIndex = State(initialValue: book.seriesIndex.map { $0.truncatingRemainder(dividingBy: 1) == 0 ? String(Int($0)) : String($0) } ?? "")
        _tags = State(initialValue: book.tags.joined(separator: ", "))
        _summary = State(initialValue: book.summary ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 8) {
                    Group {
                        if let newCoverImage {
                            Image(nsImage: newCoverImage).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            CoverView(book: book)
                        }
                    }
                    .frame(width: 160, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(radius: 3, y: 2)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let u = urls.first, let img = NSImage(contentsOf: u) else { return false }
                        newCover = u; newCoverImage = img
                        return true
                    }
                    Button("Change Cover…", action: pickCover).controlSize(.small)
                    Text("or drop an image").font(.caption).foregroundStyle(.secondary)
                }

                Form {
                    TextField("Title", text: $title)
                    TextField("Author", text: $author, prompt: Text("Separate authors with &"))
                    HStack {
                        TextField("Series", text: $series)
                        TextField("#", text: $seriesIndex).frame(width: 50)
                    }
                    TextField("Tags", text: $tags, prompt: Text("Comma separated"))
                    LabeledContent("Description") {
                        TextEditor(text: $summary)
                            .font(.body)
                            .frame(height: 110)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
                    }
                    LabeledContent("Files") {
                        HStack {
                            ForEach(book.preferredFiles, id: \.self) { f in
                                Button((f as NSString).pathExtension.uppercased()) { library.open(book, file: f) }
                                    .controlSize(.small)
                                    .help("Open \(f)")
                            }
                            Button { library.reveal([book]) } label: { Image(systemName: "folder") }
                                .controlSize(.small)
                                .help("Show in Finder")
                        }
                    }
                }
                .formStyle(.columns)
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
        .frame(width: 620)
    }

    private func pickCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let u = panel.url, let img = NSImage(contentsOf: u) else { return }
        newCover = u; newCoverImage = img
    }

    private func save() {
        var b = book
        b.title = title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? book.title
        b.author = author.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Unknown"
        b.series = series.trimmingCharacters(in: .whitespaces).nonEmpty
        b.seriesIndex = b.series == nil ? nil : Double(seriesIndex.replacingOccurrences(of: ",", with: "."))
        b.tags = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        b.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        library.update(b, newCover: newCover)
        dismiss()
    }
}
