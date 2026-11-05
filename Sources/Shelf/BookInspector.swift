import SwiftUI

struct BookInspector: View {
    let book: Book
    let coverURL: URL
    let edit: () -> Void
    @Environment(Library.self) private var library
    @Environment(InfoStore.self) private var info
    @State private var expanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CoverView(book: book, coverURL: coverURL)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(book.author).foregroundStyle(.secondary)
                    if !book.seriesLabel.isEmpty {
                        Text(book.seriesLabel).font(.callout).foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    Button("Open") { library.open(book) }.buttonStyle(.borderedProminent)
                    Button("Edit…", action: edit)
                    Spacer()
                }
                .controlSize(.regular)

                online
            }
            .padding(16)
        }
        .task(id: book.id) {
            expanded = false
            let files = book.files.map { library.fileURL(book, $0) }
            info.load(book, isbnFromFiles: {
                files.lazy.compactMap { Metadata.extract(from: $0, cover: false).isbn }.first
            })
        }
    }

    @ViewBuilder
    private var online: some View {
        switch info.state(for: book) {
        case .found(let i):
            found(i)
        case .notFound:
            facts(nil)
            description(nil)
            message("Not found on Open Library.", retry: true)
            links(nil)
        case .failed(let error):
            facts(nil)
            description(nil)
            message("Couldn't look this book up: \(error)", retry: true)
        case .loading, nil:
            facts(nil)
            description(nil)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking up…").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func found(_ i: BookInfo) -> some View {
        if let r = i.rating, r > 0 {
            HStack(spacing: 2) {
                ForEach(0..<5) { n in
                    Image(systemName: Double(n) + 0.75 <= r ? "star.fill" : Double(n) + 0.25 <= r ? "star.leadinghalf.filled" : "star")
                }
                Text(String(format: " %.1f", r)).monospacedDigit()
                if let c = i.ratingsCount { Text("(\(c) ratings)").foregroundStyle(.secondary) }
            }
            .font(.callout)
            .foregroundStyle(.orange)
        }

        facts(i)
        description(i.description)

        if !i.subjects.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Subjects").font(.caption).foregroundStyle(.secondary)
                Text(i.subjects.joined(separator: " · ")).font(.callout)
            }
        }

        let missing = (book.summary == nil && i.description != nil) || (book.isbn == nil && i.isbn != nil)
            || (book.tags.isEmpty && !i.subjects.isEmpty)
        if missing {
            Button("Save Details to Book") {
                var b = book
                if b.summary == nil { b.summary = i.description }
                if b.isbn == nil { b.isbn = i.isbn }
                if b.tags.isEmpty { b.tags = Array(i.subjects.prefix(5)) }
                library.update(b)
            }
            .help("Fill in the missing description, ISBN and tags from \(i.source)")
        }

        links(i)
        Text("Info from \(i.source)" + (i.title.lowercased() != book.title.lowercased() ? " (matched “\(i.title)”)" : ""))
            .font(.caption2).foregroundStyle(.tertiary)
    }

    private func facts(_ i: BookInfo?) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
            if let y = i?.year { row("Published", y) }
            if let p = i?.pages { row("Pages", "\(p)") }
            if let p = i?.publisher { row("Publisher", p) }
            if let isbn = book.isbn ?? i?.isbn { row("ISBN", isbn) }
            row("Formats", book.formats)
            row("Added", book.added.formatted(date: .abbreviated, time: .omitted))
        }
        .font(.callout)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func description(_ online: String?) -> some View {
        if let text = book.summary ?? online {
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.callout)
                    .lineLimit(expanded ? nil : 8)
                    .textSelection(.enabled)
                if text.count > 400 {
                    Button(expanded ? "Less" : "More") { expanded.toggle() }
                        .buttonStyle(.link).font(.callout)
                }
            }
        }
    }

    private func message(_ text: String, retry: Bool) -> some View {
        HStack {
            Text(text).font(.callout).foregroundStyle(.secondary)
            if retry {
                Button("Retry") {
                    let files = book.files.map { library.fileURL(book, $0) }
                    info.load(book, isbnFromFiles: { files.lazy.compactMap { Metadata.extract(from: $0, cover: false).isbn }.first }, force: true)
                }
                .buttonStyle(.link)
            }
        }
    }

    private func links(_ i: BookInfo?) -> some View {
        let query = (book.isbn ?? i?.isbn) ?? "\(book.title) \(book.author)"
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return HStack(spacing: 14) {
            if let link = i?.link { Link(i?.source ?? "Open", destination: link) }
            if let gr = URL(string: "https://www.goodreads.com/search?q=\(q)") { Link("Goodreads", destination: gr) }
            if let sg = URL(string: "https://app.thestorygraph.com/browse?search_term=\(q)") { Link("StoryGraph", destination: sg) }
        }
        .font(.callout)
    }
}
