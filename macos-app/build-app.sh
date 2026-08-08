#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
BUILD_DIR="$SCRIPT_DIR/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
RELEASE_DIR="$PROJECT_DIR/release"
APP_NAME="西瓜老师工作台"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
APP_ZIP="$RELEASE_DIR/$APP_NAME-macOS.zip"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
ICON_SOURCE="$PROJECT_DIR/public/assets/xigua-teacher-user-cutout.png"
ICON_MASTER="$BUILD_DIR/AppIcon-1024.png"
ICONSET="$SCRIPT_DIR/XiguaWorkbench/Assets.xcassets/AppIcon.appiconset"

if [[ ! -d "$DEVELOPER_DIR" ]]; then
  echo "需要先安装完整 Xcode。" >&2
  exit 1
fi

for tool in swiftc sips xcodebuild codesign ditto plutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "缺少构建工具：$tool" >&2
    exit 1
  fi
done

mkdir -p "$BUILD_DIR" "$RELEASE_DIR" "$ICONSET"
rm -rf "$APP_BUNDLE" "$APP_ZIP"

DEVELOPER_DIR="$DEVELOPER_DIR" swiftc -O \
  -framework AppKit \
  "$SCRIPT_DIR/Support/create-icon.swift" \
  -o "$BUILD_DIR/create-icon"

"$BUILD_DIR/create-icon" "$ICON_SOURCE" "$ICON_MASTER"

create_icon_size() {
  local pixels="$1"
  local filename="$2"
  sips -z "$pixels" "$pixels" "$ICON_MASTER" --out "$ICONSET/$filename" >/dev/null
}

create_icon_size 16 icon_16x16.png
create_icon_size 32 icon_16x16@2x.png
create_icon_size 32 icon_32x32.png
create_icon_size 64 icon_32x32@2x.png
create_icon_size 128 icon_128x128.png
create_icon_size 256 icon_128x128@2x.png
create_icon_size 256 icon_256x256.png
create_icon_size 512 icon_256x256@2x.png
create_icon_size 512 icon_512x512.png
create_icon_size 1024 icon_512x512@2x.png

DEVELOPER_DIR="$DEVELOPER_DIR" xcodebuild \
  -quiet \
  -project "$SCRIPT_DIR/XiguaWorkbench.xcodeproj" \
  -scheme XiguaWorkbench \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Xcode 构建完成但没有找到 App。" >&2
  exit 1
fi

ditto "$BUILT_APP" "$APP_BUNDLE"
codesign --force --deep --options runtime \
  --entitlements "$SCRIPT_DIR/XiguaWorkbench/XiguaWorkbench.entitlements" \
  --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$APP_ZIP"

echo "原生 macOS App 构建完成："
echo "$APP_BUNDLE"
echo "$APP_ZIP"
