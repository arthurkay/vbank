#!/usr/bin/env bash
# Installs the Linux build for the current user: bundle under ~/.local/lib/vbank,
# launcher entry and icon under ~/.local/share. Run after `flutter build linux --release`.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
BUNDLE=${1:-$ROOT/build/linux/x64/release/bundle}
[ -x "$BUNDLE/vbank" ] || { echo "no bundle at $BUNDLE (build with: flutter build linux --release)"; exit 1; }
DEST=$HOME/.local/lib/vbank
rm -rf "$DEST"; mkdir -p "$DEST" "$HOME/.local/bin" "$HOME/.local/share/applications" "$HOME/.local/share/icons/hicolor/512x512/apps"
cp -r "$BUNDLE"/. "$DEST"/
ln -sf "$DEST/vbank" "$HOME/.local/bin/vbank"
convert "$ROOT/assets/brand/icon_1024.png" -resize 512x512 "$HOME/.local/share/icons/hicolor/512x512/apps/vbank.png" 2>/dev/null \
  || cp "$ROOT/assets/brand/icon_1024.png" "$HOME/.local/share/icons/hicolor/512x512/apps/vbank.png"
sed "s|^Exec=vbank|Exec=$DEST/vbank|" "$ROOT/linux/vbank.desktop" > "$HOME/.local/share/applications/vbank.desktop"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
echo "installed: $DEST (launcher entry + icon registered)"
