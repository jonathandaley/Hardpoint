#!/bin/bash
# T525 step 4 (user 2026-11-19: "4 sounds especially good, do that"): a speed-optimised web export
# template. Godot's official web templates are optimised for SIZE; this builds the same engine
# version (tag 4.6.2-stable) with optimize=speed + production (LTO), no threads (as the T420 export).
# Everything lives under build/webbuild/ (gitignored): Godot source, emsdk 4.0.11 (Godot's own CI
# version for 4.6), a venv with SCons. Long (an hour or more on the T3500) -- run with nothing else busy.
#   tools/webbuild.sh            -> build/webbuild/godot/bin/godot.web.template_release.wasm32.nothreads.zip
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/build/webbuild
source "$W/emsdk/emsdk_env.sh" >/dev/null 2>&1
cd "$W/godot"
"$W/venv/bin/scons" platform=web target=template_release production=yes optimize=speed threads=no \
	-j"$(nproc)" 2>&1 | tail -20
ls -la bin/*.zip
