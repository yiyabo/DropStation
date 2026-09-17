#!/bin/zsh
# 一键发版：./release.sh v0.3.0 "更新说明"
set -euo pipefail

ROOT="${0:A:h}"
cd "$ROOT"

TAG="${1:?用法: ./release.sh v0.3.0 \"更新说明\"}"
NOTES="${2:-}"

./create-dmg.sh

VERSION="${TAG#v}"
DMG="$ROOT/dist/DropStation-$VERSION.dmg"
if [[ ! -f "$DMG" ]]; then
    echo "未找到 $DMG（请确认 build-app.sh 中的版本号与 $TAG 一致）" >&2
    exit 1
fi

gh release create "$TAG" "$DMG" "$DMG.sha256" \
    --title "DropStation $TAG" \
    --notes "$NOTES"

printf '已发布 %s（含 DMG 与 SHA256 校验和）\n' "$TAG"
