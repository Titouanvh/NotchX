#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
architecture="${1:-$(uname -m)}"
case "$architecture" in
    arm64|x86_64) architectures=("$architecture") ;;
    universal) architectures=(arm64 x86_64) ;;
    *) printf 'Usage: %s [arm64|x86_64|universal]\n' "$0" >&2; exit 2 ;;
esac

mkdir -p build
staging="$(mktemp -d "$PWD/build/.staging.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
bundle="$staging/NotchX.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp Resources/Info.plist "$bundle/Contents/"
for resource in Resources/*; do
    if [[ "$resource" != Resources/Info.plist && "$resource" != Resources/Entitlements.plist ]]; then
        cp -R "$resource" "$bundle/Contents/Resources/"
    fi
done

binaries=()
sdk="$(xcrun --sdk macosx --show-sdk-path)"
for entry in "${architectures[@]}"; do
    binary="$staging/NotchX-$entry"
    xcrun swiftc -swift-version 5 -O -target "$entry-apple-macosx14.0" -sdk "$sdk" \
        -module-cache-path "$PWD/build/.module-cache" Sources/*.swift -o "$binary"
    binaries+=("$binary")
done
if [[ "${#binaries[@]}" -eq 2 ]]; then
    xcrun lipo -create "${binaries[@]}" -output "$bundle/Contents/MacOS/NotchX"
else
    cp "${binaries[0]}" "$bundle/Contents/MacOS/NotchX"
fi
codesign --force --sign - --options runtime --entitlements Resources/Entitlements.plist "$bundle"
codesign --verify --strict "$bundle"
if [[ -d build/NotchX.app ]]; then
    mv build/NotchX.app "$staging/previous.app"
fi
if ! mv "$bundle" build/NotchX.app; then
    if [[ -d "$staging/previous.app" ]]; then
        mv "$staging/previous.app" build/NotchX.app
    fi
    exit 1
fi
printf '%s\n' "$PWD/build/NotchX.app"
