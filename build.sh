#!/bin/bash
# NotchDash 构建脚本：只用 Command Line Tools，不需要完整 Xcode
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotchDash"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 收集所有源文件（Providers 子目录可能为空，用 find 避免 glob 报错）
SOURCES=$(find Sources -name "*.swift" | sort | tr '\n' ' ')
echo "编译源文件: $(echo $SOURCES | wc -w | tr -d ' ') 个"

swiftc -swift-version 5 -O \
  -framework AppKit -framework SwiftUI -framework IOKit \
  -o "$APP/Contents/MacOS/$APP_NAME" \
  $SOURCES

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>app.notchdash.NotchDash</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <!-- 纯后台 App：不进 Dock、不抢焦点 -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# 图标。必须在签名之前拷进去，否则签名不覆盖后加的文件
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

# 本地临时签名，避免每次运行被 Gatekeeper 拦
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "⚠️  签名跳过（不影响本地运行）"

echo "✅ 构建完成: $APP"
