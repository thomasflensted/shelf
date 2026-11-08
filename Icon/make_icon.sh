#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
WORK=$(mktemp -d)
ICONSET="$WORK/Shelf.iconset"
mkdir "$ICONSET"
swift make_icon.swift shelf-icon.jpg "$WORK/icon_1024.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$WORK/icon_1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns -o Shelf.icns "$ICONSET"
sips -s format png -z 256 256 shelf-icon.jpg --out ../docs/icon.png >/dev/null
rm -rf "$WORK"
