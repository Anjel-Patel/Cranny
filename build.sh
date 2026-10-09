#!/bin/zsh
# Builds Cranny.app, signs it ad hoc and (with --install) copies it to /Applications.
#   ./build.sh            build into ./build/Cranny.app
#   ./build.sh --install  build, install to /Applications and relaunch
set -euo pipefail

cd "${0:A:h}"
APP_NAME="Cranny"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"
ARCH="$(uname -m)"

echo "› Compiling app"
swift build -c release --arch "$ARCH" 2>&1 | grep -E "error|warning: unre|Compiling|Build" || true
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { echo "Build failed"; exit 1; }

echo "› Compiling media helper"
mkdir -p "$BUILD_DIR/helper"
clang -dynamiclib -fobjc-arc -O2 -arch "$ARCH" -mmacosx-version-min=14.0 \
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

echo "› Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
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
rm -f "$BUILD_DIR/$APP_NAME.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/$APP_NAME.zip"

if [[ "${1:-}" == "--install" ]]; then
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
