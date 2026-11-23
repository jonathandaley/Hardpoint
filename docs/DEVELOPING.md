# Developing Hardpoint

Notes for working on the game itself. Players want the [README](../README.md); the online
server's operator wants [`deploy/README.md`](../deploy/README.md).

## Run from source

Godot **4.6.2** (official build).

```bash
godot --headless --import    # after cloning AND after every pull: imports new art, builds the class cache
godot .                      # play
```

Running the game never imports anything: a pulled PNG that wasn't imported loads as nothing
(Denali showed untextured on clones that pulled it and ran `godot .`, 2026-11-16).

## Tests

```bash
python3 tools/run_suite.py                          # everything: scenarios, gd_probes, security (~30 min)
python3 tools/run_suite.py --net wifi,bad --no-probes   # netcode under loss / jitter (~15 min)
python3 tools/selftest.py                           # determinism baseline (sim / RNG changes)
```

- `tools/gd_probes/` -- small scenes, one per behaviour; a probe fails by `push_error`.
- `tools/scenarios/` + `tools/oracles/` -- scripted multiplayer runs (`tools/mp_harness/`) checked by oracles.
- Hand-run probes write a profile: prefix them with `XDG_DATA_HOME=<scratch dir>`.

## Dedicated server by hand

The online server runs from the kit in [`deploy/`](../deploy/README.md). For a LAN game or a test:

```bash
godot --headless --path . -- --server                   # WebSocket on TCP 8910, accounts on TCP 8911
./hardpoint_X.Y.Z.x86_64 --headless -- --server=9000 --team-size=3 --min-players=2
```

| Flag | Meaning |
|---|---|
| `--server[=PORT]` | host; accounts listen on PORT + 1 (TCP, TLS) |
| `--team-size=N` | bots fill each team to N (default 5); `--no-bots` turns that off |
| `--mode=beacons\|rush\|deathmatch` | game mode (default beacons) |
| `--map=res://resources/maps/<Map>.tres` | fixed map |
| `--min-players=N` | ready players needed to start (default 1) |
| `--lobby-idle=S` | once enough are ready, the rest get S seconds (default 180) |

Players use FIND MATCH > JOIN with the server's address. The match starts 5 s after everyone is
ready and returns to the lobby when it ends. Open TCP on both ports (the game port and the one above it).

## Releasing

1. Gameplay changed (anything beyond menus, HUD, art and sound)? Raise `Game.NET_VERSION` and
   update `NET_SIG` -- [`docs/SECURITY.md`](SECURITY.md) rule 15 says what counts.
2. Set `config/version` in `project.godot`; full suite green.
3. Export both builds:
   ```bash
   godot --headless --path . --export-release "Linux"   build/hardpoint_X.Y.Z.x86_64
   godot --headless --path . --export-release "Windows" build/hardpoint_X.Y.Z.exe
   ```
   The Windows preset reads `build/templates/windows_release_x86_64.exe` (git-ignored), taken from
   the official `Godot_v4.6.2-stable_export_templates.tpz`:
   `unzip -j <tpz> templates/windows_release_x86_64.exe -d build/templates/`.
   Use `--export-release`: debug templates put "(DEBUG)" in the window title.
4. Publish a GitHub release with both builds, `LICENSE` and `THIRD_PARTY.md`.
5. The same day, update the online server: [`deploy/README.md`](../deploy/README.md), "Updating to a
   new version".

## Architecture

`InputSource -> Player -> Mech -> Weapons`. The player is not the mech: `PlayerInputSource` and
`AIInputSource` are interchangeable, so bots drive mechs through the same code as people. A mech
fires whatever weapon scenes sit on its hardpoints without knowing their types -- a new weapon is a
new `.tscn`. The server is authoritative; clients predict their own mech and interpolate the rest
from 20 Hz snapshots. Match state lives in the arena scene and resets on scene change.

| Where | What |
|---|---|
| `autoloads/` | `Game` (session, networking, lobby; profile + settings in `game/`), `SoundManager`, `VFX` -- the only autoloads |
| `scripts/` | mechs (`Mech`, `BipedLegs`, `MechVisuals`), weapons, AI, HUD, hangar, lobby, settings |
| `scripts/maps/` | one script per map scene (geometry, spawns, beacons) |
| `scenes/` | `arena/` (the match), `maps/`, `mech/`, `weapons/`, `beacon/`, `ui/` |
| `resources/` | `MechDef` / `MapDef` / ability `.tres` files |
| `tools/` | tests, harness, art and map tools (`.gdignore`d: the editor skips it, the tests load from it by path) |

## Docs

| File | What |
|---|---|
| [`docs/DESIGN.md`](DESIGN.md) | why things are built the way they are -- read before an architectural change |
| `SPEC.md` | goal, constraints, invariants (§V), task queue (§T), bug log (§B) |
| `SPEC_DONE.md` | finished task rows (`tools/spec_sweep.py` moves them) |
| [`docs/SECURITY.md`](SECURITY.md) | the network trust rules |
| `AUTODEBUG_BRIEF.md` / `AUTODEBUG_JOURNAL.md` | how the automated work loop runs, and its log |
