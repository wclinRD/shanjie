#!/bin/bash
# Build release script for shanjie
# This script builds the Rust core and creates a release bundle.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Create release directory if it doesn't exist
RELEASE_DIR="$SCRIPT_DIR/release"
mkdir -p "$RELEASE_DIR"

echo "Building Rust core..."
export PATH="/opt/homebrew/bin:$PATH"
cargo build --release --locked -p core

echo "Building Swift package..."
swift build --package-path macos --configuration release

echo "Creating release bundle..."
# Build the app bundle
make bundle

echo "Copying app to release directory..."
if [ -d "build/善解輸入法.app" ]; then
    cp -r "build/善解輸入法.app" "$RELEASE_DIR/"
    echo "Release bundle created at $RELEASE_DIR/善解輸入法.app"
else
    echo "Error: build/善解輸入法.app not found"
    exit 1
fi

echo "Build release completed successfully!"
