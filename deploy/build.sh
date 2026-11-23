#!/bin/sh
# Step 1 (as yourself, no sudo): pack the game for the server -> deploy/out.local/
set -eu
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/bin/godot}"
mkdir -p deploy/out.local
python3 tools/security/run_security.py > deploy/out.local/security.log 2>&1 || {
	echo "The attack suite found a problem (deploy/out.local/security.log). Not building."; exit 1; }
"$GODOT" --headless --path . --export-pack "Linux" deploy/out.local/hardpoint.pck > deploy/out.local/export.log 2>&1
rm -rf deploy/out.local/web && mkdir -p deploy/out.local/web  # T422: the browser version, served beside it
"$GODOT" --headless --path . --export-release "Web" deploy/out.local/web/index.html >> deploy/out.local/export.log 2>&1
[ -f deploy/out.local/web/index.pck ] || { echo "The web export failed (deploy/out.local/export.log)."; exit 1; }
cp -L "$GODOT" deploy/out.local/godot
git rev-parse --short HEAD > deploy/out.local/version.txt
echo "Built $(cat deploy/out.local/version.txt). Next: sudo deploy/install.sh"
