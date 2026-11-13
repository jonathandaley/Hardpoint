#!/bin/sh
# Step 2 (sudo): install or update the server from deploy/out.local/. Safe to run again.
set -eu
[ "$(id -u)" = 0 ] || { echo "Run with sudo."; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/out.local"
[ -f "$OUT/hardpoint.pck" ] && [ -f "$OUT/godot" ] || { echo "Run deploy/build.sh first."; exit 1; }
DATA=/var/lib/hardpoint
USERDIR="$DATA/godot/app_userdata/Hardpoint"

id hardpoint >/dev/null 2>&1 || useradd --system --home-dir "$DATA" --shell /usr/sbin/nologin hardpoint
install -d -o root -g root -m 755 /opt/hardpoint /etc/hardpoint
install -d -o hardpoint -g hardpoint -m 700 "$DATA" "$DATA/godot" "$DATA/godot/app_userdata" "$USERDIR"
install -o root -g root -m 755 "$OUT/godot" /opt/hardpoint/godot
install -o root -g root -m 644 "$OUT/hardpoint.pck" "$OUT/version.txt" /opt/hardpoint/
install -o root -g root -m 644 "$HERE/override.cfg" /opt/hardpoint/override.cfg

# The server's identity: the private key players' games check the server against (T401).
# Installed once; never overwritten (a new key would lock every player out until they update).
if [ ! -f "$USERDIR/account_tls.key" ]; then
	[ -f "$HERE/identity.local/account_tls.key" ] || { echo "deploy/identity.local/ is missing: see deploy/README.md"; exit 1; }
	install -o hardpoint -g hardpoint -m 600 "$HERE/identity.local/account_tls.key" "$HERE/identity.local/account_tls.crt" "$USERDIR/"
fi

[ -f /etc/hardpoint/server.env ] || install -o root -g root -m 644 "$HERE/server.env" /etc/hardpoint/server.env
install -o root -g root -m 644 "$HERE/hardpoint.nft" /etc/hardpoint/hardpoint.nft
install -o root -g root -m 644 "$HERE/hardpoint.service" "$HERE/hardpoint-firewall.service" \
	"$HERE/hardpoint-backup.service" "$HERE/hardpoint-backup.timer" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now hardpoint-firewall.service hardpoint-backup.timer
systemctl restart hardpoint-firewall.service
systemctl enable hardpoint.service
systemctl restart hardpoint.service
sleep 3
systemctl --no-pager --lines=8 status hardpoint.service || true
echo "Installed version $(cat /opt/hardpoint/version.txt). Logs: journalctl -u hardpoint -f"
