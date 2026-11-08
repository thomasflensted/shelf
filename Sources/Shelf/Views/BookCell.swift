import SwiftUI

struct BookCell: View {
    let book: Book
    let selected: Bool
    let coverURL: URL
    let onKindle: Bool
    let kindleName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book, coverURL: coverURL)
                .aspectRatio(2 / 3, contentMode: .fit)
                .coverStyle()
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                        .padding(-4)
                )
                .overlay(alignment: .bottomTrailing) {
                    if onKindle {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .font(.system(size: 18))
                            .shadow(radius: 2)
                            .padding(5)
                            .help("On \(kindleName)")
                    }
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(book.title).font(.callout.weight(.medium)).lineLimit(2)
                Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }
}
