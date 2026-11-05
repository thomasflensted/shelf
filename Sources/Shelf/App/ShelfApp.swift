import SwiftUI

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library = Library()
    @State private var kindle = Kindle()
    @State private var info = InfoStore()

    var body: some Scene {
        Window("Shelf", id: "main") {
            RootView()
                .environment(library)
                .environment(kindle)
                .environment(info)
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Books…") { library.presentAddPanel() }
                    .keyboardShortcut("o")
                if library.hasCalibreLibrary {
                    Button("Import Calibre Library") { library.importCalibreLibrary() }
                }
                Divider()
                Button("Choose Library Folder…") { library.chooseLibraryFolder() }
                Button("Show Library in Finder") { NSWorkspace.shared.open(library.root) }
            }
        }
    }
}
