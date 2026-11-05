# Shelf

A barebones native macOS ebook library. A small replacement for the parts of Calibre I actually use.

- Cover grid or sortable list, with search over title, author, series and tags
- Drop files or folders on the window, or use ⌘O, to add books (EPUB, MOBI, AZW/AZW3, PDF, CBZ…)
- Reads title, author and cover from EPUB, MOBI/AZW3 and PDF files
- File → Import Calibre Library copies `~/Calibre Library` in, keeping metadata, covers and all formats. The original is never modified.
- Edit title, author, series, tags, description and cover (⌘I)
- Double-click to open in your default reader. Right-click for Open Format, Show in Finder, Send to Kindle (shown when a USB Kindle is mounted) and Move to Trash
- Books live in plain folders: `~/Books/Author/Title/` plus `library.json` (change it with File → Choose Library Folder…)

Build and install to `~/Applications`:

```
./build.sh
```
