#!/bin/bash
# Monta um DMG estilo "arraste o app pra pasta Applications".
# Usa: scripts/create_dmg.sh
# Requer que dist/iNetPeek.app já exista (build de Release).

set -euo pipefail

APP_NAME="iNetPeek"
APP_PATH="dist/${APP_NAME}.app"
FINAL_DMG="dist/${APP_NAME}.dmg"
VOLUME_NAME="${APP_NAME}"
TMP_DMG="dist/${APP_NAME}-tmp.dmg"
STAGING_DIR="dist/dmg-staging"

if [[ ! -d "$APP_PATH" ]]; then
    echo "erro: $APP_PATH não existe — rode o build primeiro." >&2
    exit 1
fi

echo "→ preparando staging"
rm -rf "$STAGING_DIR" "$TMP_DMG" "$FINAL_DMG"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

SIZE_MB=$(du -sm "$STAGING_DIR" | awk '{print $1}')
SIZE_MB=$((SIZE_MB + 30))

echo "→ criando DMG temporário (${SIZE_MB}MB)"
hdiutil create -srcfolder "$STAGING_DIR" -volname "$VOLUME_NAME" \
    -fs HFS+ -format UDRW -size ${SIZE_MB}m "$TMP_DMG" >/dev/null

echo "→ montando"
MOUNT_OUT=$(hdiutil attach -readwrite -noverify -noautoopen "$TMP_DMG")
MOUNT_DEV=$(echo "$MOUNT_OUT" | grep -E '^/dev/' | head -1 | awk '{print $1}')
MOUNT_POINT=$(echo "$MOUNT_OUT" | grep -E '^/dev/' | tail -1 | awk '{for(i=3;i<=NF;i++) printf "%s%s", $i, (i<NF?" ":"")}')
echo "  montado em: $MOUNT_POINT"

echo "→ configurando layout via Finder (pode pedir permissão de automação)"
osascript <<EOF || echo "  (osascript falhou — DMG vai funcionar mas sem layout custom)"
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 200, 760, 560}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set position of item "${APP_NAME}.app" of container window to {150, 170}
        set position of item "Applications" of container window to {410, 170}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
EOF

sync

echo "→ desmontando"
hdiutil detach "$MOUNT_DEV" -quiet || hdiutil detach "$MOUNT_DEV" -force

echo "→ convertendo pra UDZO comprimido"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" >/dev/null

rm -f "$TMP_DMG"
rm -rf "$STAGING_DIR"

echo "✓ $FINAL_DMG"
ls -lh "$FINAL_DMG"
