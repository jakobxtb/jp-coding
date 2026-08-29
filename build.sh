#!/bin/zsh
# Baut "JP Coding.app". Aufruf:  ./build.sh [Zielordner] [--with-skills <Ordner>]
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
DEST="${1:-/Applications}"
[[ "$DEST" == --* ]] && DEST="/Applications"
APP="$DEST/JP Coding.app"
RES="$APP/Contents/Resources"

SKILLS_SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with-skills) SKILLS_SRC="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "==> Ziel: $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES/server/ui" "$RES/bin" \
         "$RES/JPData/chats" "$RES/JPData/claude-config/skills" \
         "$RES/JPData/claude-config/skills-disabled" "$RES/JPData/runtime"

cp "$SRC/Info.plist"                 "$APP/Contents/Info.plist"
cp "$SRC/launcher.sh"                "$APP/Contents/MacOS/JP Coding"
chmod +x "$APP/Contents/MacOS/JP Coding"
cp "$SRC/server/jp_server.py"        "$RES/server/jp_server.py"
cp "$SRC/server/ui/"*               "$RES/server/ui/"
cp "$SRC/bin/models.json"            "$RES/bin/models.json"

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
    [ -e "$d" ] || continue                 # defekte Symlinks ueberspringen
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    cp -RL "$d" "$RES/JPData/claude-config/skills/$n" 2>/dev/null || true
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
rm -rf "$TMP"

touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
echo "==> Fertig: $APP"
