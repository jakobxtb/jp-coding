#!/bin/zsh
# JP Coding - Startet Backend und Fenster.
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
UID_=$(id -u)

fail(){ osascript -e "display alert \"JP Coding\" message \"$1\" as critical" >/dev/null 2>&1; exit 1 }

PY=""
for c in /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
  [ -x "$c" ] && PY="$c" && break
done
[ -z "$PY" ] && fail "Python 3 nicht gefunden. Bitte Xcode Command Line Tools installieren: xcode-select --install"

# Datenordner: im Paket wenn beschreibbar, sonst Application Support
DATA="$RES/JPData"
if ! ( mkdir -p "$DATA" 2>/dev/null && touch "$DATA/.wtest" 2>/dev/null ); then
  DATA="$HOME/Library/Application Support/JP Coding"; mkdir -p "$DATA"
fi
rm -f "$DATA/.wtest"
PORTFILE="$DATA/port"; LOG="$DATA/server.log"

# Proxy starten falls vorhanden
if [ -f "$HOME/Library/LaunchAgents/com.freeclaudecode.server.plist" ]; then
  launchctl print "gui/$UID_/com.freeclaudecode.server" >/dev/null 2>&1 || \
    launchctl bootstrap "gui/$UID_" "$HOME/Library/LaunchAgents/com.freeclaudecode.server.plist" >/dev/null 2>&1
  launchctl kickstart "gui/$UID_/com.freeclaudecode.server" >/dev/null 2>&1
fi

alive(){ [ -f "$PORTFILE" ] && curl -sf -m 1 "http://127.0.0.1:$(cat "$PORTFILE")/api/status" >/dev/null 2>&1 }
if ! alive; then
  rm -f "$PORTFILE"
  nohup "$PY" "$RES/server/jp_server.py" >> "$LOG" 2>&1 &
  for i in {1..100}; do alive && break; /bin/sleep 0.25; done
fi
alive || fail "Backend startet nicht. Log: $LOG"

URL="http://127.0.0.1:$(cat "$PORTFILE")/"
for B in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
         "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
  if [ -x "$B" ]; then
    exec "$B" --app="$URL" --user-data-dir="$DATA/browser" \
         --window-size=1360,900 --no-first-run --no-default-browser-check
  fi
done
open "$URL"
