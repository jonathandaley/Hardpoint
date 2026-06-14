# MP_M0_BRIEF — Claude Code session: determinism + instrumentation foundation

Paste this whole file at the start of a fresh Sonnet Claude Code session on
pomegranate. It is self-contained. If `MP_AUTODEBUG_PLAN.md` is in the repo, it
is the source of truth for the overall harness; this brief covers M0 only.
DESIGN.md and SPEC.md in the repo are ground truth — read them before writing code.

---

## 0. Hard constraints (read before any code)

These are non-negotiable. Violating one is a failed task, not a tradeoff.

From SPEC §C / §V, the ones that bite this work:

- **V1 / V2:** all control input routes through an `InputSource`; `Mech` never
  reads raw input. The Player/Pawn split exists already — the new replay input
  is a drop-in at the InputSource layer, nothing in `Mech` changes.
- **V5:** only `Game.gd`, `SoundManager.gd`, `VFX.gd` are autoloads. Do **not**
  add a fourth. Snapshot logging hangs off `Game.gd`; the seeded RNG lives on
  `Game.gd`.
- **V13:** offline computation (the log diff) goes in `tools/*.py`. The live
  snapshot logging is the one justified exception (a Python tool cannot read
  live game state) — keep it minimal.
- **V14:** scenario specs and snapshot dicts use untyped `var`, not typed
  Resource access.
- **V16:** no em-dashes in `.gd` comments. Hyphens only. This crashes the
  parser on Linux.
- `get_parent()` in `@onready` is unreliable — lazy-init any cross-boundary refs
  on first call, not in `@onready`.
- `randomize()` reseeds from system entropy and is a determinism killer — it must
  be removed from gameplay paths (see build step 2).
- Commit policy: **commit, do not push.** Repo stays private.
- **3-strikes:** if any approach fails three times with distinct variations,
  stop, report symptoms, and propose a pivot. Do not keep tweaking a failing
  strategy.

## 1. Session posture

This is the foundation phase, not the unattended fixing loop. Unlike the future
autonomous run, **this session is allowed and expected to halt and report** when
it hits a real wall or a decision that changes the architecture. Front-loaded
autonomy applies to M3, not here. Jonathan will review the M0 deliverable before
anything runs unattended.

So: where the 3-strikes rule fires, **stop and report — do not silently pivot.**
Escalate the choice.

## 2. Phase 0 — orient and report first

Before writing anything:

1. Read DESIGN.md, SPEC.md, and the actual multiplayer code (whatever exists of
   T40: `MultiplayerAPI` setup, `MultiplayerSynchronizer` nodes, any
   server/client split, the existing `InputSource` implementations).
2. Report back, concisely: what netcode exists today, where the
   `MultiplayerSynchronizer` targets sit relative to the torso/legs hierarchy,
   every `randf()` / `randi()` / `randomize()` call site, and where per-mech
   state (pos, rotation, health, ammo, lock target, beacon ownership) actually
   lives.
3. **Halt-and-report condition:** if there is no real server/client distinction
   yet — i.e. nothing to desync — say so and stop. Do not build a harness around
   netcode that does not exist. That report is itself a valid M0 outcome and
   tells Jonathan T40 is still greenfield.

If the substrate is there, proceed.

## 3. Build order

Front-loaded low-risk work first; the one hard piece (deterministic multi-peer
mode) is isolated until everything that feeds it exists.

| Step | Work | Done when |
|---|---|---|
| 1 | **Central seeded RNG.** Add a `RandomNumberGenerator` on `Game.gd` (`Game.rng`), seeded from the scenario seed. Route every gameplay RNG call through it. Remove all `randomize()` from gameplay paths. | `grep` shows zero unseeded `randf`/`randi` and zero `randomize()` in gameplay code; all RNG flows through `Game.rng`. |
| 2 | **Snapshot logging via `Game.gd`**, validated against the *existing* running game first (normal run, not the harness). Flag-gated (`--sync-log` arg / `Game.sync_logging_enabled`). Writes JSONL per physics tick + an event stream (schema in §4). | With the flag on, a normal run emits well-formed JSONL with sane values; `rot_local` and `rot_global` both populate and differ correctly on the decoupled torso; flag off emits nothing and costs nothing. Commit this **separately** from any logic change. |
| 3 | **`ReplayInputSource`** — a sibling of `PlayerInputSource` / `AIInputSource` that feeds a fixed, timestamped input sequence per peer from a scenario file. | A scenario's input sequence drives a mech headlessly; `Mech` reads nothing raw (V1); replaying the same sequence produces the same motion. |
| 4 | **Two-process headless loopback mode.** Server and one client each run as a separate `godot --headless` process; server binds loopback, client connects to it. Both driven by `ReplayInputSource` via their scenario file. No single-process hacks -- identical code path to a real LAN game. | A canned scenario runs end to end, two log files written (`server.jsonl`, `client_1.jsonl`), no errors on stderr. |
| 5 | **Determinism self-test + minimal diff.** `tools/sync_diff.py` (Python stdlib only, no new deps) compares two log files for epsilon-equality and reports the first divergence (tick, mech, field, magnitude). Run the canned scenario twice with the identical seed and script. | Two runs of the identical seed are epsilon-identical per `sync_diff.py`. **This green baseline is Jonathan's checkpoint.** |

Defer the full oracle library (transform/health/beacon/etc. classifiers) to M1 —
M0 only needs the pairwise epsilon diff for the self-test.

## 4. Snapshot schema (self-contained)

One JSON object per physics tick per tracked entity, appended to that peer's
file. JSONL: append-only, crash-safe, trivially parsed.

```
{
  "tick": 412,
  "wall_ms": 6840,
  "peer": 1,
  "role": "client",
  "mech_id": "slip_0",
  "pos": [12.40, 0.00, -8.13],
  "rot_local":  [0.0, 0.7071, 0.0, 0.7071],
  "rot_global": [0.0, 0.3827, 0.0, 0.9239],
  "health": 740,
  "ammo": {"hp_left": 3, "hp_right": 8},
  "lock_target": "cesh_2",
  "team": 0,
  "abilities": {"jump": 12.0}
}
```

Event stream (same or sibling file): `{tick, peer, type, mech_id, payload,
rpc_seq}` for fired / hit / captured / died / spawned / ability. `rpc_seq` is a
monotonic per-channel sequence number so dropped or reordered RPCs become
detectable in M1.

**Log both `rot_local` and `rot_global`.** `MultiplayerSynchronizer` syncs the
local transform; the mech's facing lives on a child node (decoupled torso). The
likeliest transform desync is "synced node correct, resolved global facing
wrong," and it is invisible unless both are captured. Validate this in step 2.

## 5. Known risks (where the stop-loss applies)

- **Physics-level nondeterminism.** Even with all RNG seeded and inputs scripted,
  the self-test may surface divergence from physics ordering or frame-timing
  dependence between the two processes. If so, report it (which fields, what
  magnitude, whether it is bounded or growing). Do not attempt to rewrite physics.
  This is a finding; the fix is widening oracle tolerances, which is a judgment
  call for Jonathan to approve before M1.
- **Process orchestration.** Launching, synchronizing, and cleanly killing two
  headless Godot processes from a harness script is straightforward but fiddly
  (wait for server-ready signal before client connects, collect exit codes, handle
  crashes). If the orchestration itself takes more than one failed approach,
  stop and report rather than accumulating complexity.

## 6. Deliverable

A green determinism baseline: the canned scenario runs headless, emits the full
JSONL schema, and two identical-seed runs are epsilon-identical via
`tools/sync_diff.py`. Plus the Phase 0 report. That is the whole of M0 and the
point at which Jonathan looks before M1.

## 7. Commit and environment notes

- Commit frequently, never push. One commit per build step; message format e.g.
  `M0.2: snapshot logging via Game.gd [autodebug]`. Instrumentation commits stay
  separate from any logic change.
- Shell is tcsh; run Godot from the terminal so stdout is readable (already the
  workflow). M0 needs no new Python packages (stdlib only) — if that changes,
  name the aptitude package and let Jonathan install it; do not run the install.
- When the self-test goes green (the deliverable), signal completion with the
  terminal bell or `paplay` so it is noticed.
- Optional, low priority: record the M0 steps as tasks in ROADMAP.md / SPEC §T if
  you want them tracked. Not required for the deliverable.
