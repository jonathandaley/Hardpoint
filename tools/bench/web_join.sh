#!/bin/bash
# T422: browser end-to-end -- a real Firefox (under Xvfb) loads the web build and joins a real dedicated
# server over WebSocket (?join=127.0.0.1:<port>); passes when the server logs the browser peer joining
# and it stays connected. Needs a fresh web export (build/web; this exports one unless NO_EXPORT=1).
#   tools/bench/web_join.sh [seconds=40]
# Kills only its own Firefox / servers by PID -- never the user's browser.
set -u
SECS=${1:-40}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCR=$ROOT/build/scratch/web_join
GODOT=${GODOT:-$HOME/bin/godot}
HTTP=8766
GAME=28990
rm -rf "$SCR"; mkdir -p "$SCR/profile" "$SCR/data"
if [ "${NO_EXPORT:-0}" != 1 ]; then
	"$GODOT" --headless --path "$ROOT" --export-release "Web" "$ROOT/build/web/index.html" > "$SCR/export.log" 2>&1
fi
cat > "$SCR/profile/user.js" <<'EOF'
user_pref("devtools.console.stdout.content", true);
user_pref("media.autoplay.default", 0);
user_pref("media.volume_scale", "0.0");
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
EOF
XDG_DATA_HOME=$SCR/data "$GODOT" --headless --path "$ROOT" -- --server=$GAME --team-size=2 --min-players=2 > "$SCR/server.log" 2>&1 &
GS=$!
python3 -m http.server $HTTP --bind 127.0.0.1 --directory "$ROOT/build/web" >/dev/null 2>&1 &
SRV=$!
sleep 4
xvfb-run -a firefox --no-remote --profile "$SCR/profile" --width 1280 --height 720 \
	"http://127.0.0.1:$HTTP/index.html?join=127.0.0.1:$GAME" > "$SCR/firefox.txt" 2>&1 &
FF=$!
sleep "$SECS"
kill $FF 2>/dev/null; sleep 2; kill -9 $FF 2>/dev/null
for i in 1 2 3; do
	for p in $(pgrep -f -- "--profile $SCR/profile" 2>/dev/null); do kill $p 2>/dev/null; done
	sleep 1
done
kill $SRV $GS 2>/dev/null
grep -a "joined from\|left\|disconnect" "$SCR/server.log" | head -5
grep -a "\[MPEntry\]\|SCRIPT ERROR" "$SCR/firefox.txt" | sed 's/^.*\(\[MPEntry\]\)/\1/' | head -5
if grep -q "joined from 127.0.0.1" "$SCR/server.log"; then echo "web_join: PASS"; else echo "web_join: FAIL (logs: $SCR)"; exit 1; fi
