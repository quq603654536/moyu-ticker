#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/dist/摸鱼盯盘.app"
BUILD="$ROOT/.build/native"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ "${1:-}" == "--current-arch" ]]; then
    ARCHES="$(uname -m)"
else
    ARCHES="arm64 x86_64"
fi
BINARIES=()
for ARCH in $ARCHES; do
    TARGET="$ARCH-apple-macosx13.0"
    MOD="$BUILD/$ARCH"
    mkdir -p "$MOD"
    echo "Building ${ARCH}…"
    xcrun swiftc -O -swift-version 5 -target "$TARGET" -sdk "$SDK" \
        -module-cache-path "$BUILD/cache" -parse-as-library \
        -emit-module -emit-library -static -module-name MarketCore \
        Sources/MarketCore/*.swift -emit-module-path "$MOD/MarketCore.swiftmodule" \
        -o "$MOD/libMarketCore.a"
    xcrun swiftc -O -swift-version 5 -target "$TARGET" -sdk "$SDK" \
        -module-cache-path "$BUILD/cache" -parse-as-library -I "$MOD" \
        Sources/TickerBar/*.swift "$MOD/libMarketCore.a" -o "$MOD/TickerBar"
    BINARIES+=("$MOD/TickerBar")
done
if [[ ${#BINARIES[@]} -gt 1 ]]; then
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/TickerBar"
else
    cp "${BINARIES[0]}" "$APP/Contents/MacOS/TickerBar"
fi
cp scripts/Info.plist "$APP/Contents/Info.plist"
if [[ ! -f "$BUILD/AppIcon.icns" || "scripts/make-icon.swift" -nt "$BUILD/AppIcon.icns" ]]; then
    xcrun swiftc scripts/make-icon.swift -o "$BUILD/make-icon" -module-cache-path "$BUILD/cache"
    "$BUILD/make-icon" "$BUILD"
    mkdir -p "$BUILD/AppIcon.iconset"
    for SIZE in 16 32 128 256 512; do
        sips -z "$SIZE" "$SIZE" "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${SIZE}x${SIZE}.png" >/dev/null
        DOUBLE=$((SIZE * 2))
        sips -z "$DOUBLE" "$DOUBLE" "$BUILD/icon.png" --out "$BUILD/AppIcon.iconset/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
    done
    iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"
fi
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/摸鱼盯盘-macOS.zip"
echo "Built: $APP"
