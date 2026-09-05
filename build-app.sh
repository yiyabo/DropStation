#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"
swift build -c release
python3 "$ROOT/generate-icon.py"

APP="$ROOT/DropStation.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/DropStation" "$APP/Contents/MacOS/DropStation"
cp "$ROOT/.build/DropStation.icns" "$APP/Contents/Resources/DropStation.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>DropStation</string>
    <key>CFBundleExecutable</key>
    <string>DropStation</string>
    <key>CFBundleIdentifier</key>
    <string>local.dropstation.app</string>
    <key>CFBundleIconFile</key>
    <string>DropStation</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>DropStation</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
IDENTITY="DropStation Development"
if security find-identity -v -p codesigning 2>/dev/null | grep "$IDENTITY" >/dev/null; then
    codesign --force --sign "$IDENTITY" "$APP" >/dev/null
    printf '已使用证书 "%s" 签名：重新构建后辅助功能授权保持有效\n' "$IDENTITY"
else
    codesign --force --sign - "$APP" >/dev/null
    printf '⚠️  使用 ad-hoc 签名：每次重新构建后都需要重新授予辅助功能权限\n' >&2
    printf '   若想保持授权稳定，可在“钥匙串访问 → 证书助理 → 创建证书”里创建一个\n' >&2
    printf '   名为 "%s"、类型为“代码签名”的证书，之后重新构建会自动使用它\n' "$IDENTITY" >&2
fi
printf 'Built %s\n' "$APP"
