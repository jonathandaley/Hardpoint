# Putting the server online (deploy kit)

Everything here runs on the machine that actually runs the game server. For
lemon.limedaley.com that is **pomegranate** (lemon only forwards the ports to it).

## What you do

1. **Forward two ports** from lemon to pomegranate: UDP 25575 (the game) and TCP 25576
   (accounts: sign-up / log-in). Nothing else.
2. **Check the port forward keeps players' addresses** (see below). Do this before
   inviting anyone.
3. On pomegranate, in the project folder:

       deploy/build.sh            # as yourself: runs the attack suite, then packs the game
       sudo deploy/install.sh     # installs / updates and (re)starts the server

4. Watch it: `journalctl -u hardpoint -f`. Stop / start: `sudo systemctl stop|start hardpoint`.

**Updating** after new commits: run the same two commands again. Players must update
their game too whenever the network version changed (they are told "Update the game to
play here" if they have not).

## Check the port forward

The game and the firewall rules limit how much ONE ADDRESS may do (8 players, 3 joins in
progress, 60 account requests a minute, 10 sign-ups an hour). That only works if the
server sees each player's real address.

After one friend outside your network has joined, run:

    journalctl -u hardpoint | grep "joined from"

The line must show your friend's own internet address. If it shows lemon's address (or
the same address for every player), lemon is rewriting the source address: change the
forward on lemon to a plain destination rewrite (DNAT) **without** masquerade / source
NAT for these two ports. Otherwise every player arrives as one address: the ninth player
is refused, one person hammering the sign-up form locks everyone out, and a ban by
address bans everybody.

## What the kit sets up

| Piece | What it is for |
|---|---|
| user `hardpoint` | The server runs as its own user that can write only `/var/lib/hardpoint`. A bug in the game cannot touch the rest of the machine. |
| `/opt/hardpoint/` | The game pack + engine (read-only to the server). |
| `/var/lib/hardpoint/godot/app_userdata/Hardpoint/` | `accounts.cfg` (emails + password hashes), the server's key, `banned.txt`. |
| `/etc/hardpoint/server.env` | Port and options (team size, minimum players, map, mode). Edit, then restart. |
| `hardpoint-firewall.service` | Flood limits for the two ports only (`hardpoint.nft`). It does not open or close anything else. |
| journal rate limit | A flood of junk packets cannot fill the disk with log lines. Godot's own log file is off. |
| `hardpoint-backup.timer` | A copy of `accounts.cfg` every night in `/var/lib/hardpoint/backups/`, 30 kept. |

## The server's identity (`deploy/identity.local/`)

`account_tls.key` is the server's private key; `resources/account_server.crt` (in the
repo, public) is its matching certificate. Every player's game refuses to send a
password to lemon.limedaley.com unless the server proves it holds that key.

- The key is in a git-ignored folder. Never commit it, never copy it off this machine
  except as a private backup. `install.sh` copies it into the server's data folder once.
- If the key is ever lost or leaked: make a new pair, replace
  `resources/account_server.crt`, and every player must update before they can sign in.
- The certificate runs until 2034-01-01.

## Banning someone

Add a line to `/var/lib/hardpoint/godot/app_userdata/Hardpoint/banned.txt` (create it,
owned by `hardpoint`): an address (`203.0.113.9`) or an account email. It is read at
every join. To throw out someone who is connected right now, add the line and
`sudo systemctl restart hardpoint`.

## Restoring accounts from a backup

    sudo systemctl stop hardpoint
    sudo -u hardpoint cp /var/lib/hardpoint/backups/accounts-YYYY-MM-DD.cfg \
        /var/lib/hardpoint/godot/app_userdata/Hardpoint/accounts.cfg
    sudo systemctl start hardpoint

## Not covered

- Game traffic (UDP) is not encrypted (decision 2026-11-12). No password or login
  session travels on it; someone on a player's network could watch or disrupt a match.
- No email verification or password reset yet (needs the mail server).
- Keep Godot current: `build.sh` ships whatever `~/bin/godot` is.
