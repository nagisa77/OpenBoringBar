#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p "$ROOT_DIR/.home"
export HOME="$ROOT_DIR/.home"

echo "==> 1/2 pod install (自动生成 Xcode 工程 + workspace)"
pod install

echo "==> 2/2 xcodebuild (Debug/macOS)"
xcodebuild \
  -project OpenBoringBar.xcodeproj \
  -scheme OpenBoringBar \
  -configuration Debug \
  -sdk macosx \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  build
