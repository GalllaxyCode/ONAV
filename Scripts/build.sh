#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-release}"
APP="build/Hollow Signal.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS=(-swift-version 5 -sdk "$SDK" -framework AppKit -framework SceneKit -framework AVFoundation -framework QuartzCore)
if [[ "$MODE" == "debug" ]]; then
    swiftc -g -D DEBUG -Onone -target arm64-apple-macosx12.0 "${FLAGS[@]}" Sources/*.swift -o build/HollowSignal-debug
    cp build/HollowSignal-debug "$APP/Contents/MacOS/HollowSignal"
else
    swiftc -O -whole-module-optimization -target arm64-apple-macosx12.0 "${FLAGS[@]}" Sources/*.swift -o build/HollowSignal-arm64
    # Recent Apple toolchains no longer ship Intel Swift back-deployment archives.
    # Sonoma supplies the required Intel runtime directly; Apple Silicon keeps macOS 12 support.
    swiftc -O -whole-module-optimization -target x86_64-apple-macosx14.0 "${FLAGS[@]}" Sources/*.swift -o build/HollowSignal-x86_64
    lipo -create build/HollowSignal-arm64 build/HollowSignal-x86_64 -output "$APP/Contents/MacOS/HollowSignal"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$APP/Contents/Resources/"; fi
cp ASSET_CREDITS.md "$APP/Contents/Resources/"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
echo "Built $APP ($MODE)"
