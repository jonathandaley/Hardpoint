# Session recordings (T157)

Every real multiplayer session records itself so a problem you noticed can be checked
afterwards. Nothing to switch on.

- **Where:** `~/.local/share/godot/app_userdata/Hardpoint/sessions/<date_time>/` on Linux
  (`%APPDATA%\Godot\app_userdata\Hardpoint\sessions\` on Windows). One folder per session,
  newest 3 kept (~15 MB per minute of match per machine).
- **What:** per-tick state of every mech (`server.jsonl` on the host, `client_<id>.jsonl` on a
  joiner), events, beacons, and a screenshot every 10 s (`*_<tick>.jpg`). A second match in the
  same session goes to `match2/`.
- **Reporting something:** copy the session folder from **each** machine into one folder (the host's
  and the joiner's files have different names), put it under `sessions_in/` in the project folder on the dev PC (git ignores it), and say
  roughly when it happened ("about 3 minutes in"). The agent cuts that window
  (`tools/session_window.py`) and runs the checks on it.

## Marking a moment: F9 (T556)

In an online match, press **F9** when something looks wrong ("MARKED" shows at the bottom). The
mark goes into the server's recording and its log, and into your own if you record. Nothing else
needed: tools/mine_sessions.py on the dev PC lists every mark with its match time and cuts the
recording around it (build/mined/).

## The online server's recordings (T556)

The installed server records every match to `/var/lib/hardpoint-sessions/` (newest 20 matches,
~1 GB at most); `deploy/install.sh` lets the admin who ran it read that folder and the server's
journal. `python3 tools/mine_sessions.py` checks each finished match not checked before (the
server-side oracles; cross-peer checks need a client's recording too), lists F9 marks, and
prints the journal's ERROR / MARK lines since the last run. Exit 1 = something to look at.
