#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/番茄钟.app"
BUNDLE_ID="com.zhuanz.pomodoro"

echo "🍅 开始编译..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# 编译（Swift 5 语言模式，避免严格并发报错）
swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/Pomodoro" \
  "$DIR/src/main.swift" \
  -framework AppKit -framework SwiftUI -framework UserNotifications

# 拷贝图标
if [ -f "$DIR/AppIcon.icns" ]; then
  cp "$DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Info.plist：LSUIElement=1 表示菜单栏 App，不显示 Dock 图标
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>番茄钟</string>
    <key>CFBundleDisplayName</key>
    <string>番茄钟</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>Pomodoro</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc 签名（本地通知/权限需要）
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "⚠️ 签名跳过"

echo "✅ 完成：$APP"
