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
# T556: match recordings go to their own folder that the admin (whoever ran sudo) can read, for
# tools/mine_sessions.py -- accounts and the identity key stay in $DATA (700). The admin can read
# the journal too (the server's errors and F9 MARK lines); they have sudo, so nothing new.
SESS=/var/lib/hardpoint-sessions
install -d -o hardpoint -g hardpoint -m 750 "$SESS"
ADMIN="${SUDO_USER:-}"
if [ -n "$ADMIN" ] && [ "$ADMIN" != root ]; then
	command -v setfacl >/dev/null 2>&1 || apt-get install -y acl
	setfacl -R -m "u:$ADMIN:rX" -m "d:u:$ADMIN:rX" "$SESS"
	for J in /var/log/journal /run/log/journal; do
		[ -d "$J" ] && setfacl -R -m "u:$ADMIN:rX" -m "d:u:$ADMIN:rX" "$J"
	done
fi
install -o root -g root -m 755 "$OUT/godot" /opt/hardpoint/godot
install -o root -g root -m 644 "$OUT/hardpoint.pck" "$OUT/version.txt" /opt/hardpoint/
install -o root -g root -m 644 "$HERE/override.cfg" /opt/hardpoint/override.cfg
# T422: the browser version's page, served by Caddy's file server (its own unit; apt's default
# Caddy site on port 80 is switched off when this installs Caddy)
if ! command -v caddy >/dev/null 2>&1; then
	apt-get install -y caddy
	systemctl disable --now caddy.service || true
fi
rm -rf /opt/hardpoint/web
cp -r "$OUT/web" /opt/hardpoint/web
chmod -R u=rwX,go=rX /opt/hardpoint/web

# The server's identity: the private key players' games check the server against (T401).
# Installed once; never overwritten (a new key would lock every player out until they update).
if [ ! -f "$USERDIR/account_tls.key" ]; then
	[ -f "$HERE/identity.local/account_tls.key" ] || { echo "deploy/identity.local/ is missing: see deploy/README.md"; exit 1; }
	install -o hardpoint -g hardpoint -m 600 "$HERE/identity.local/account_tls.key" "$HERE/identity.local/account_tls.crt" "$USERDIR/"
fi

[ -f /etc/hardpoint/server.env ] || install -o root -g root -m 644 "$HERE/server.env" /etc/hardpoint/server.env
install -o root -g root -m 644 "$HERE/hardpoint.nft" /etc/hardpoint/hardpoint.nft
install -o root -g root -m 644 "$HERE/hardpoint.service" "$HERE/hardpoint-firewall.service" \
	"$HERE/hardpoint-backup.service" "$HERE/hardpoint-backup.timer" "$HERE/hardpoint-web.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now hardpoint-firewall.service hardpoint-backup.timer
systemctl restart hardpoint-firewall.service
systemctl enable hardpoint.service hardpoint-web.service
systemctl restart hardpoint.service hardpoint-web.service
sleep 3
systemctl --no-pager --lines=8 status hardpoint.service || true
echo "Installed version $(cat /opt/hardpoint/version.txt). Logs: journalctl -u hardpoint -f"
