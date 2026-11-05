import SwiftUI

struct CoverView: View {
    let book: Book
    // Passed in rather than read from the environment: Table cells don't inherit environment objects and crash.
    let coverURL: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
        .task(id: book.coverKey) {
            image = book.hasCover ? await ThumbnailCache.shared.image(at: coverURL, key: book.coverKey) : nil
        }
    }

    private var placeholder: some View {
        let hue = Double(book.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 360 }) / 360
        return ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.35, brightness: 0.55),
                                    Color(hue: hue, saturation: 0.45, brightness: 0.35)],
                           startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                Text(book.title).font(.system(size: 13, weight: .semibold, design: .serif))
                Text(book.author).font(.system(size: 10))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.92))
            .padding(10)
            .minimumScaleFactor(0.5)
        }
    }
}
