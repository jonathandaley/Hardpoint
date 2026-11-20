#!/bin/bash
# T525: browser frame-time baseline on this machine (pomegranate = the T3500 target).
#   tools/bench/web_bench.sh <map> <allies,enemies> <seconds> [extra url flags, e.g. "&weapons=MachineGunLight"]
# Serves build/web, opens it in a scratch Firefox profile on :0 (muted, uncapped, console -> stdout),
# prints the overlay's "[Perf]" lines (one per 5 s). Run with NOTHING else busy (a suite skews it).
# Kills only its own Firefox / server by PID -- never the user's browser.
set -u
MAP=${1:-Corvette}; BOTS=${2:-4,5}; SECS=${3:-90}; EXTRA=${4:-}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
SCR=$ROOT/build/scratch/web_bench
PORT=8765
mkdir -p "$SCR"
rm -rf "$SCR/profile"; mkdir -p "$SCR/profile"
cat > "$SCR/profile/user.js" <<'EOF'
user_pref("devtools.console.stdout.content", true);
user_pref("layout.frame_rate", 0);
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.blocking_policy", 0);
user_pref("media.volume_scale", "0.0");
user_pref("privacy.reduceTimerPrecision", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
EOF
python3 -m http.server $PORT --bind 127.0.0.1 --directory "${WEB_DIR:-$ROOT/build/web}" >/dev/null 2>&1 &
SRV=$!
sleep 1
DISPLAY=:0 firefox --no-remote --profile "$SCR/profile" --width 1280 --height 720 \
	"http://127.0.0.1:$PORT/index.html?perf&sp&map=$MAP&bots=$BOTS$EXTRA" > "$SCR/out.txt" 2>&1 &
FF=$!
sleep "$SECS"
kill $FF 2>/dev/null; sleep 2; kill -9 $FF 2>/dev/null
# the content processes are children of $FF's profile: end any left by the profile path
for i in 1 2 3; do
	for p in $(pgrep -f -- "--profile $SCR/profile" 2>/dev/null); do kill $p 2>/dev/null; done
	sleep 1
done
kill $SRV 2>/dev/null
grep -a "\[Perf\]" "$SCR/out.txt" | sed 's/^.*\[Perf\]/[Perf]/'
