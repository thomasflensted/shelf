# Shelf

A barebones native macOS ebook library: a small replacement for the parts of Calibre I actually use.

## Library

- Cover grid or sortable list, with search over title, author, series and tags
- Drop files or folders on the window, or use ⌘O, to add books (EPUB, MOBI, AZW/AZW3, PDF, CBZ…)
- Reads title, author, cover and ISBN from EPUB, MOBI/AZW3 and PDF files
- File → Import Calibre Library copies `~/Calibre Library` in, keeping metadata, covers and all formats. The original is never modified.
- Info panel (⌘I): details, rating, description and subjects from [Open Library](https://openlibrary.org), with Google Books filling gaps when it responds. No API keys needed.
- Edit title, author, description and cover with ⌘E or by double-clicking a book
- Books live in plain folders: `~/Books/Author/Title/` plus `library.json` (change it with File → Choose Library Folder…)

## Kindle

For Kindles that mount as a USB drive (10th-gen Paperwhite and older):

- The Kindle appears in the sidebar when plugged in
- Send books with ⌘K. AZW3 is preferred, then MOBI, then PDF.
- Green checks mark library books that are already on the device
- Device view: storage use, every book with its size and source (Amazon, Shelf, or only on the Kindle), Remove, Copy to Shelf
- Clean Up removes leftover `.sdr` folders from deleted books. Amazon books' extra data folders are matched by ASIN, so they're never treated as leftovers.
- Eject (⌘E)

## Build

Requires macOS 14+ and Xcode command line tools.

```
./build.sh
```

This builds a release binary, wraps it in `Shelf.app`, ad-hoc signs it and installs it to `~/Applications`.

## Tests

```
swift test
```

They run on every pull request and push to `main` via GitHub Actions.
