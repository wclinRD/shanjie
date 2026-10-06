#!/bin/bash
# Build release script for shanjie
# This script builds the Rust core, creates the input method zip, and generates the installer package.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create release directory if it doesn't exist
RELEASE_DIR="$SCRIPT_DIR/release"
mkdir -p "$RELEASE_DIR"

# Get version from the built app or use default
VERSION="0.2.0"
if [ -d "build/善解輸入法.app" ]; then
    VERSION=$(defaults read "$SCRIPT_DIR/build/善解輸入法.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "$VERSION")
fi

echo "Building Rust core..."
export PATH="/opt/homebrew/bin:$PATH"
cargo build --release --locked -p core

echo "Building Swift package..."
swift build --package-path macos --configuration release

echo "Creating release bundle..."
# Build the app bundle
make bundle

if [ ! -d "build/善解輸入法.app" ]; then
    echo "Error: build/善解輸入法.app not found"
    exit 1
fi

echo "Copying app to release directory..."
# Copy the built app bundle to the release directory
mkdir -p "$RELEASE_DIR/善解輸入法.app"
cp -R "build/善解輸入法.app/." "$RELEASE_DIR/善解輸入法.app/"

echo "Creating input method zip file..."
ZIP_FILE="$RELEASE_DIR/shanjie-$VERSION.zip"
# Create zip with the app bundle inside
cd "$RELEASE_DIR"
rm -f "shanjie-$VERSION.zip"
zip -r -y "shanjie-$VERSION.zip" "善解輸入法.app"
cd "$SCRIPT_DIR"

echo "Building installer app..."
# Build the installer app with the zip file
SHANJIE_VERSION="$VERSION" ./scripts/build-installer.sh "release" "$ZIP_FILE"

echo "Creating installer package..."
# Create the shanjie-installer.pkg from the installer app
cd "$RELEASE_DIR"
pkgbuild --root "安裝善解輸入法.app" --identifier com.nyanako.shanjie.installer --version "$VERSION" --install-location "/Library/Input Methods" "shanjie-installer.pkg"

echo "Creating final distribution package..."
# Create the final 善解輸入法-0.2.0.pkg from the distribution.xml and the installer package
productbuild --distribution "distribution.xml" --package-path "shanjie-installer.pkg" "善解輸入法-$VERSION.pkg"

echo "Release bundle created at $RELEASE_DIR/善解輸入法-$VERSION.pkg"
echo "Build release completed successfully!"
