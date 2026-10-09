#!/bin/zsh
# Builds Cranny.app, signs it ad hoc and zips it.
#   ./build.sh               build for this Mac into ./build/Cranny.app (+ build/Cranny.zip)
#   ./build.sh --universal   build for both Apple silicon and Intel (used for releases)
#   ./build.sh --install     also install to /Applications and relaunch
set -euo pipefail

cd "${0:A:h}"
APP_NAME="Cranny"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"

INSTALL=false
ARCHS=("$(uname -m)")
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --universal) ARCHS=(arm64 x86_64) ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done
ARCH_FLAGS=()
for a in "${ARCHS[@]}"; do ARCH_FLAGS+=(-arch "$a"); done

BINS=()
for a in "${ARCHS[@]}"; do
  echo "› Compiling app ($a)"
  swift build -c release --arch "$a" 2>&1 | grep -E "error|warning: unre|Build" || true
  BIN="$(swift build -c release --arch "$a" --show-bin-path)/$APP_NAME"
  [[ -x "$BIN" ]] || { echo "Build failed for $a"; exit 1; }
  # Newer SwiftPM versions reuse one output folder for every architecture, so keep a copy.
  mkdir -p "$BUILD_DIR/bin-$a"
  cp "$BIN" "$BUILD_DIR/bin-$a/$APP_NAME"
  BINS+=("$BUILD_DIR/bin-$a/$APP_NAME")
done

echo "› Compiling media helper"
mkdir -p "$BUILD_DIR/helper"
clang -dynamiclib -fobjc-arc -O2 "${ARCH_FLAGS[@]}" -mmacosx-version-min=14.0 \
  -framework Foundation Helper/MediaHelper.m -o "$BUILD_DIR/helper/MediaHelper.dylib"

if [[ ! -f "$BUILD_DIR/AppIcon.icns" || Tools/make-icon.swift -nt "$BUILD_DIR/AppIcon.icns" ]]; then
  echo "› Drawing icon"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET" && mkdir -p "$ICONSET"
  swift Tools/make-icon.swift "$BUILD_DIR/icon-1024.png" >/dev/null
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$BUILD_DIR/AppIcon.icns"
fi

echo "› Assembling $APP (${ARCHS[*]})"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf "APPL????" > "$APP/Contents/PkgInfo"
cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp Helper/media-helper.pl "$APP/Contents/Resources/media-helper.pl"
cp "$BUILD_DIR/helper/MediaHelper.dylib" "$APP/Contents/Frameworks/MediaHelper.dylib"

echo "› Signing (ad hoc)"
codesign --force --sign - "$APP/Contents/Frameworks/MediaHelper.dylib"
codesign --force --sign - --identifier io.github.rdbms234.Cranny "$APP"
codesign --verify --strict "$APP"

echo "› Zipping"
rm -f "$BUILD_DIR/$APP_NAME.zip" "$BUILD_DIR/$APP_NAME.zip.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"
# Published next to the zip so install.sh and the in-app updater can verify downloads.
(cd "$BUILD_DIR" && shasum -a 256 "$APP_NAME.zip" > "$APP_NAME.zip.sha256")

if $INSTALL; then
  echo "› Installing to $INSTALL_DIR"
  pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  # Keep a single copy around so Spotlight/Launchpad and the URL scheme only see the installed app.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
  rm -rf "$APP"
  open "$INSTALL_DIR/$APP_NAME.app"
  echo "✓ Installed and launched $INSTALL_DIR/$APP_NAME.app"
else
  echo "✓ Built $APP"
fi
