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
