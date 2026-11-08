import SwiftUI

struct BookInspector: View {
    let book: Book
    let coverURL: URL
    let edit: () -> Void
    @Environment(Library.self) private var library
    @Environment(InfoStore.self) private var info
    @State private var expanded = false

    private var files: [URL] { book.files.map { library.fileURL(book, $0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CoverView(book: book, coverURL: coverURL)
                    .aspectRatio(2 / 3, contentMode: .fit)
                    .frame(maxWidth: 170)
                    .coverStyle()
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                    Text(book.author).foregroundStyle(.secondary)
                    if !book.seriesLabel.isEmpty {
                        Text(book.seriesLabel).font(.callout).foregroundStyle(.tertiary)
                    }
                }

                Button("Edit…", action: edit)

                online
            }
            .padding(16)
        }
        .task(id: book.id) {
            expanded = false
            info.load(book, files: files)
        }
    }

    @ViewBuilder
    private var online: some View {
        let state = info.state(for: book)
        if case .found(let i) = state {
            found(i)
        } else {
            facts(nil)
            description(nil)
            lookupStatus(state)
        }
    }

    @ViewBuilder
    private func lookupStatus(_ state: LookupState?) -> some View {
        switch state {
        case .notFound:
            message("Not found on Open Library.")
            links(nil)
        case .failed(let error):
            message("Couldn't look this book up: \(error)")
        default:
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
                ForEach(Array(RatingStars.symbols(for: r).enumerated()), id: \.offset) { Image(systemName: $0.element) }
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

        let filled = book.fillingGaps(from: i)
        if filled != book {
            Button("Save Details to Book") { library.update(filled) }
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

    private func message(_ text: String) -> some View {
        HStack {
            Text(text).font(.callout).foregroundStyle(.secondary)
            Button("Retry") { info.load(book, files: files, force: true) }
                .buttonStyle(.link)
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
