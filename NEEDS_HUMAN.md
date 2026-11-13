# NEEDS_HUMAN.md -- things the agent can't decide (feel, taste, design)

Each entry: date | task | what to look at | where | why the agent stopped.
Delete an entry once you've answered it (or answer inline and the agent will act).

- 2026-11-09 | T350 | Elite pilots now bring their own hangars and styles (scripts/BotNames.gd ELITE_KIT). E.g. Vantablack: 5 sniper mechs, fights from 1.8x the usual distance; Wraith: Cesh / Slip shotguns, closes to 0.6x; Inexorable: heavy MG / shotgun rushers that barely retreat; Bastion and Obsidian: shielded / Patience defenders; Sable and Deadlock: rocket / arc / aerial lock-on flankers. Every kit sticks to weapons that fit its mechs. Say if any pilot should fly something else. | scripts/BotNames.gd | FYI / taste
### This will take a while to check on. Leaving here for now.
- 2026-11-12 | T266 | The server is ready to install on pomegranate: `deploy/build.sh`, then `sudo deploy/install.sh` (deploy/README.md explains every piece). Two things only you can do: (1) forward UDP 25575 + TCP 25576 from lemon to pomegranate WITHOUT masquerade / source NAT -- if lemon rewrites the source address every player looks like one address and the per-address limits hit everyone at once (the README has a one-line check); (2) tell me when it is up, and I switch the game's Join / Sign-in defaults to lemon.limedaley.com. | deploy/README.md | needs sudo + the router
- 2026-11-12 | T401 | The server's private key is in `deploy/identity.local/` on pomegranate (git-ignored, never pushed). Keep a private backup of that folder: if it is lost, every player must update the game before they can sign in again. | deploy/identity.local/ | FYI
