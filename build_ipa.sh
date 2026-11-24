#!/bin/bash
# Windows/Linux-free alternative to the Makefile; run on macOS.
set -e
cd "$(dirname "$0")"

APP_NAME=SwordFS

echo "[*] Generating project..."
xcodegen -spec project.yml

echo "[*] Building (unsigned)..."
rm -rf build
mkdir -p build
xcodebuild -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    clean build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS=""

APP="build/Build/Products/Release-iphoneos/$APP_NAME.app"
echo "[*] Faking-signing with ldid + entitlements..."
ldid -S"$APP_NAME/SwordFS.entitlements" "$APP/$APP_NAME"

echo "[*] Packaging IPA..."
mkdir -p build/Payload
cp -r "$APP" build/Payload/
(cd build && zip -qry "$APP_NAME.ipa" Payload)

echo "[+] Done: build/$APP_NAME.ipa"
echo "    Install via SparseBox / SideStore-style installer that supports"
echo "    arbitrary entitlements (NOT TrollStore on 18.1.1)."
