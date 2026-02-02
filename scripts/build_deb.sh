#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION_LINE="$(grep '^version:' pubspec.yaml | awk '{print $2}')"
VERSION="${VERSION_LINE%%+*}"
ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"

echo "Building Flutter release..."
flutter build linux --release

STAGE_DIR="$ROOT_DIR/dist/deb"
APP_DIR="$STAGE_DIR/opt/sticky-notes"
DEBIAN_DIR="$STAGE_DIR/DEBIAN"
ICON_DIR="$STAGE_DIR/usr/share/icons/hicolor/scalable/apps"
ICON_DIR_512="$STAGE_DIR/usr/share/icons/hicolor/512x512/apps"
ICON_NAME="sticky-notes-check"
DESKTOP_DIR="$STAGE_DIR/usr/share/applications"

rm -rf "$STAGE_DIR"
mkdir -p "$APP_DIR" "$DEBIAN_DIR" "$ICON_DIR" "$ICON_DIR_512" "$DESKTOP_DIR"

cp -r build/linux/x64/release/bundle/* "$APP_DIR/"

cp packaging/debian/sticky-notes.desktop "$DESKTOP_DIR/sticky-notes.desktop"
cp assets/logo.svg "$ICON_DIR/${ICON_NAME}.svg"

if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 512 -h 512 assets/logo.svg -o "$ICON_DIR_512/${ICON_NAME}.png"
fi

sed "s/^Version:.*/Version: ${VERSION}/" packaging/debian/control \
  | sed "s/^Architecture:.*/Architecture: ${ARCH}/" \
  > "$DEBIAN_DIR/control"

cp packaging/debian/postinst "$DEBIAN_DIR/postinst"
cp packaging/debian/postrm "$DEBIAN_DIR/postrm"
chmod 755 "$DEBIAN_DIR/postinst" "$DEBIAN_DIR/postrm"

DEB_NAME="sticky-notes_${VERSION}_${ARCH}.deb"
dpkg-deb --build "$STAGE_DIR" "$ROOT_DIR/dist/$DEB_NAME"

echo "Built: dist/$DEB_NAME"
