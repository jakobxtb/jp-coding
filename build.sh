#!/bin/zsh
# Baut die native "JP Coding.app" (SwiftUI).
# Aufruf:  ./build-native.sh [Zielordner] [--with-skills <Ordner>]
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
MAC="$SRC/mac"

DEST="/Applications"
SKILLS_SRC=""
args=("$@")
i=1
while [ $i -le ${#args} ]; do
  a="${args[$i]}"
  case "$a" in
    --with-skills) i=$((i+1)); SKILLS_SRC="${args[$i]}" ;;
    -*) ;;
    *) DEST="$a" ;;
  esac
  i=$((i+1))
done

APP="$DEST/JP Coding.app"
RES="$APP/Contents/Resources"
echo "==> Ziel: $APP"

BUILD="$(mktemp -d)"
echo "==> Kompiliere Swift ..."
swiftc -O -parse-as-library \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --show-sdk-path)" \
  -o "$BUILD/JP Coding" \
  "$MAC"/*.swift

echo "==> Bundle bauen"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES/bin" \
         "$RES/JPData/chats" "$RES/JPData/claude-config/skills" \
         "$RES/JPData/claude-config/skills-disabled" "$RES/JPData/runtime"
mv "$BUILD/JP Coding" "$APP/Contents/MacOS/JP Coding"
chmod +x "$APP/Contents/MacOS/JP Coding"
cp "$SRC/bin/models.json" "$RES/bin/models.json"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>JP Coding</string>
  <key>CFBundleDisplayName</key><string>JP Coding</string>
  <key>CFBundleIdentifier</key><string>com.jakobpapaj.jpcoding</string>
  <key>CFBundleVersion</key><string>4.0</string>
  <key>CFBundleShortVersionString</key><string>4.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>JP Coding</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
</dict>
</plist>
PLIST

cat > "$RES/JPData/claude-config/settings.json" <<'JSON'
{
  "permissions": {
    "deny": [
      "Read(~/.claude/**)", "Edit(~/.claude/**)", "Write(~/.claude/**)",
      "Edit(~/.zshrc)", "Write(~/.zshrc)", "Edit(~/.zprofile)", "Write(~/.zprofile)",
      "Read(~/.fcc/.env)", "Edit(~/.fcc/.env)", "Write(~/.fcc/.env)"
    ]
  }
}
JSON

if [ -n "$SKILLS_SRC" ] && [ -d "$SKILLS_SRC" ]; then
  echo "==> Skills aus $SKILLS_SRC"
  for d in "$SKILLS_SRC"/*; do
    [ -e "$d" ] || continue
    [ -d "$d" ] || continue
    cp -RL "$d" "$RES/JPData/claude-config/skills/$(basename "$d")" 2>/dev/null || true
  done
  find "$RES/JPData/claude-config/skills" -name ".DS_Store" -delete 2>/dev/null || true
  echo "    $(find "$RES/JPData/claude-config/skills" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') Skills"
fi

echo "==> Icon"
PY=$(command -v python3 || echo /usr/bin/python3)
TMP=$(mktemp -d)
"$PY" "$SRC/icon.py" "$TMP/jp.png" >/dev/null
mkdir -p "$TMP/i.iconset"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$TMP/jp.png" --out "$TMP/i.iconset/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$TMP/jp.png" --out "$TMP/i.iconset/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/i.iconset" -o "$RES/AppIcon.icns"
rm -rf "$TMP" "$BUILD"

codesign --force --deep --sign - "$APP" 2>/dev/null || echo "    (ad-hoc Signatur uebersprungen)"
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "==> Fertig: $APP"
