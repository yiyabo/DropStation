#!/bin/zsh
# 生成可拖拽安装的 DMG：./create-dmg.sh
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

./build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "DropStation.app/Contents/Info.plist")
VOLNAME="DropStation"
DIST="$ROOT/dist"
STAGING="$DIST/staging"
MOUNT_DIR="/Volumes/$VOLNAME"
RW_DMG="$DIST/DropStation-rw.dmg"
FINAL_DMG="$DIST/DropStation-$VERSION.dmg"

# 1. 组装 DMG 内容：应用本体 + Applications 快捷方式 + 背景引导图
rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp -R "DropStation.app" "$STAGING/DropStation.app"
ln -sfn /Applications "$STAGING/Applications"
python3 generate-dmg-background.py "$STAGING/.background/background.png"

# 2. 生成读写镜像，挂载后用 Finder 设置图标布局与背景，再压成只读分发镜像
rm -f "$RW_DMG" "$FINAL_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" \
    -ov -format UDRW -fs HFS+ "$RW_DMG" >/dev/null
# 同名卷若残留则先卸载，保证挂载点干净
hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
hdiutil attach "$RW_DMG" -mountpoint "$MOUNT_DIR" -nobrowse >/dev/null
# 等 Finder 注意到新卷
for _ in 1 2 3 4 5; do
    [ -e "$MOUNT_DIR/.background" ] && break
    sleep 1
done
sleep 1

if osascript <<OSA
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {0, 0, 660, 400}
        set arrangement of the icon view options of the container window to not arranged
        set icon size of the icon view options of the container window to 128
        set background picture of the icon view options of the container window to file ".background:background.png"
        set position of item "DropStation.app" of container window to {180, 170}
        set position of item "Applications" of container window to {480, 170}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
OSA
then
    echo "已设置拖拽安装界面（应用图标 + Applications 快捷方式 + 背景引导）"
else
    echo "⚠️  未能设置背景与图标位置（Finder 自动化未授权），DMG 将使用默认布局" >&2
    echo "    在终端中手动运行本脚本，并在系统弹窗中允许“控制 Finder”即可获得完整布局" >&2
fi

# 等待 Finder 写入 .DS_Store 后卸载（Finder 可能短暂占用卷，重试几次）
sync
detached=0
for _ in 1 2 3 4 5; do
    if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
        detached=1
        break
    fi
    sleep 1
done
if (( ! detached )); then
    hdiutil detach "$MOUNT_DIR" -force >/dev/null 2>&1 || true
fi

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGING"

printf '已生成 %s\n' "$FINAL_DMG"
