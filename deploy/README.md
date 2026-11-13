# Running the online server

Everything here happens on **pomegranate**, the machine that runs the server.
lemon.limedaley.com only forwards the ports to it.

Players connect to **lemon.limedaley.com:25574**.

- [Everyday commands](#everyday-commands): start, stop, restart, status, logs
- [Updating to a new version](#updating-to-a-new-version)
- [Firewall: what is automatic](#firewall-what-is-automatic)
- [First-time setup](#first-time-setup)
- [Settings](#settings): team size, map, mode, idle wait
- [Banning someone](#banning-someone)
- [Account backups](#account-backups)
- [The server's private key](#the-servers-private-key)
- [What the kit installs](#what-the-kit-installs)

## Everyday commands

| To do this | Run |
|---|---|
| Stop the server | `sudo systemctl stop hardpoint` |
| Start it | `sudo systemctl start hardpoint` |
| Restart it (after changing settings or the ban list) | `sudo systemctl restart hardpoint` |
| See if it is running | `systemctl status hardpoint` |
| Watch the log live (Ctrl+C to stop watching) | `journalctl -u hardpoint -f` |
| See who joined, and from where | `journalctl -u hardpoint \| grep "joined from"` |
| Stop it starting at boot | `sudo systemctl disable hardpoint` |
| Make it start at boot again | `sudo systemctl enable hardpoint` |

It starts on its own at every boot, and restarts itself five seconds after a crash.

## Updating to a new version

From the project folder, after pulling new commits:

    deploy/build.sh            # as yourself: runs the attack suite, then packs the game
    sudo deploy/install.sh     # installs the new pack and restarts the server

`build.sh` refuses to build if the attack suite finds a problem. Accounts, settings, the
ban list and the key are kept. Players must update their game too whenever the network
version changed; until they do, they are told "Update the game to play here".

## Firewall: what is automatic

- **Flood limits: automatic.** `install.sh` loads them, and they reload at every boot
  (`hardpoint-firewall.service`). They only drop excess traffic aimed at the two game
  ports (too many new connections from one address, or from everyone at once). They
  open, close or touch nothing else on the machine.
- **Opening the ports: not done by the kit.** Pomegranate had no firewall running when
  the kit was written (2026-11-12), so nothing blocks them. If you ever add a firewall,
  allow **UDP 25574** and **TCP 25575**.
- **The forward on lemon: yours to set up.** See [First-time setup](#first-time-setup).

To check the flood limits are loaded: `sudo nft list table inet hardpoint`.
To switch them off: `sudo systemctl stop hardpoint-firewall`.

## First-time setup

1. **Forward two ports** from lemon to pomegranate: **UDP 25574** (the game) and
   **TCP 25575** (sign-up / log-in). Nothing else.
2. **Install**, from the project folder on pomegranate:

       deploy/build.sh
       sudo deploy/install.sh

3. **Check the forward keeps players' addresses.** Do this before inviting anyone.
   After one friend outside your network has joined, run:

       journalctl -u hardpoint | grep "joined from"

   The line must show your friend's own internet address. If it shows lemon's address,
   or the same address for every player, lemon is rewriting the source address. Change
   the forward on lemon to a plain destination rewrite (DNAT), **without** masquerade or
   source NAT for these two ports.

   Why it matters: the server's limits count per address (8 players, 3 joins in
   progress, 60 account requests a minute, 10 sign-ups an hour). If every player arrives
   as one address, the ninth player is refused, one person spamming the sign-up form
   locks everyone out, and a ban by address bans everybody.

## Settings

Edit `/etc/hardpoint/server.env`, then `sudo systemctl restart hardpoint`.

- `GAME_PORT`: the game port (UDP). The account port (TCP) is always this plus one.
  Change the forward on lemon and the two numbers in `/etc/hardpoint/hardpoint.nft` to
  match, then `sudo systemctl restart hardpoint-firewall`.
- `SERVER_OPTS`: any of
  - `--team-size=N`: mechs per team, 1 to 6 (bots fill the empty places)
  - `--min-players=N`: how many players must be ready before a match can start
  - `--no-bots`: no bots
  - `--mode=beacons` or `--mode=deathmatch`
  - `--map=res://resources/maps/<Name>.tres`
  - `--lobby-idle=N`: seconds an unready player gets, once enough others are ready,
    before the match starts without them (default 180, never less than 30)

`install.sh` never overwrites this file once it exists.

## Banning someone

Add a line to `/var/lib/hardpoint/godot/app_userdata/Hardpoint/banned.txt`: an address
(`203.0.113.9`) or an account email. Lines starting with `#` are comments.

    sudo -u hardpoint nano /var/lib/hardpoint/godot/app_userdata/Hardpoint/banned.txt

It is read at every join, so no restart is needed for the next join. To throw out
someone who is connected right now, add the line and restart the server.

## Account backups

A copy of `accounts.cfg` is made every night at 04:30 in `/var/lib/hardpoint/backups/`;
the last 30 are kept. To restore one:

    sudo systemctl stop hardpoint
    sudo -u hardpoint cp /var/lib/hardpoint/backups/accounts-YYYY-MM-DD.cfg \
        /var/lib/hardpoint/godot/app_userdata/Hardpoint/accounts.cfg
    sudo systemctl start hardpoint

## The server's private key

`deploy/identity.local/account_tls.key` is the server's private key, and
`resources/account_server.crt` (in the repo, public) is its matching certificate. Every
player's game refuses to send a password to lemon.limedaley.com unless the server proves
it holds that key.

- The key's folder is git-ignored. Never commit it, and never copy it anywhere except a
  private backup. `install.sh` copies it into the server's data folder the first time.
- If the key is ever lost or leaked: make a new pair, replace
  `resources/account_server.crt`, and every player must update before they can sign in.
- The certificate is valid until 2034-01-01.

## What the kit installs

| Piece | What it is for |
|---|---|
| user `hardpoint` | The server runs as its own user and can write only `/var/lib/hardpoint`. A bug in the game cannot touch the rest of the machine. |
| `/opt/hardpoint/` | The game pack and engine (read-only to the server). |
| `/var/lib/hardpoint/godot/app_userdata/Hardpoint/` | `accounts.cfg` (emails and password hashes), the server's key, `banned.txt`. |
| `/etc/hardpoint/server.env` | Port and options ([Settings](#settings)). |
| `hardpoint.service` | The server itself. |
| `hardpoint-firewall.service` | The flood limits (`/etc/hardpoint/hardpoint.nft`). |
| journal rate limit | A flood of junk packets cannot fill the disk with log lines. Godot's own log file is off. |
| `hardpoint-backup.timer` | The nightly account backup. |

## Not covered yet

- Game traffic (UDP) is not encrypted (decision 2026-11-12). No password or login
  session travels on it; someone on a player's network could watch or disrupt a match.
- No email verification or password reset (needs the mail server).
- Keep Godot current: `build.sh` ships whatever `~/bin/godot` is.
