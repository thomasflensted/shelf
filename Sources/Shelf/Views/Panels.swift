import AppKit
import UniformTypeIdentifiers

enum Panels {
    static func chooseBooks() -> [URL] {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = "Choose books, or a folder (such as a Calibre library) to import everything in it."
        panel.prompt = "Add"
        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseLibraryFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use as Library"
        panel.message = "Choose a folder to keep your books in. An existing Shelf library will be opened."
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
