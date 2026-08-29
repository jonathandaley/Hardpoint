# MP_AUTODEBUG_PLAN.md — Autonomous Multiplayer Debugging Harness

Companion to SPEC.md (canonical; tracks this work as T133-T135) and MP_PLAN.md. Target: set-and-forget agentic
debugging of multiplayer state divergence, zero interaction once running.

---

## 0. Purpose and the honest envelope

The goal is a harness that lets a Claude Code session reproduce, diagnose, patch,
and confirm multiplayer desync bugs unattended for hours, with all decisions
front-loaded. What is realistic to expect:

- **Highly feasible:** the harness itself, structured logging, the comparison and
  oracle tools, deterministic reproduction, a regression suite, and automatic
  classification of every divergence into one of three patterns. This is plain
  engineering and reliable.
- **Feasible with guardrails:** autonomous *fixing* of **logic** desync bugs that
  reproduce deterministically and have a clear oracle — wrong node synced,
  unsynced side-effect on an event, a missing or mis-ordered RPC, a prediction
  sign or frame-count error. The agent can genuinely close many of these with
  nobody watching.
- **Lower yield:** timing and latency bugs. These are nondeterministic, need
  tolerance-based oracles, and fixes are subtler. The agent can surface and
  characterize them; clean fixes are hit-or-miss.
- **Out of scope, by design:** visual smoothing artifacts, input *feel*, audio
  desync, animation phase mismatch that does not touch gameplay transforms. The
  agent must never attempt these and never block waiting on you for them.

Calibration: expect real, committed progress on the deterministic logic-desync
queue, and a clean BLOCKED writeup (not spinning) on everything else.

---

## 1. Determinism is prerequisite zero

Everything rests on this. If the harness is nondeterministic, the agent chases
ghosts: a fix passes once, fails on rerun, the agent thinks it regressed, and
churns forever. That is the failure mode that kills unattended runs.

Before any autonomous debugging is trustworthy, three things must hold:

1. **Scripted input replay.** No live input, no unseeded AI. Add a
   `ReplayInputSource` (a sibling of `PlayerInputSource` / `AIInputSource`,
   per V1/V2) that feeds a fixed, timestamped input sequence per peer. The
   Player/Pawn split already makes this a drop-in.
2. **Seeded RNG everywhere.** Audit every `randf()` / `randi()` / `randomize()`
   site (spread, spawn jitter, bot decisions) and route through one seeded
   source. Pass the seed into the scenario. This audit is itself work item one
   and is mechanical.
3. **Headless two-process execution.** Server and client each run as a separate
   `--headless` Godot process communicating over loopback ENet — identical code
   path to a real LAN game. Determinism is judged on the **physics tick stream**,
   not render frames.

**Determinism self-test (meta-oracle):** run the identical seed + script twice
(two pairs of processes) and diff the logs. Any divergence between run 1 and
run 2 of the same input is a nondeterminism bug (hidden RNG, frame-timing
dependence) and must be fixed *before* the rest of the suite is believed. This
single test catches the most insidious class for free.

---

## 2. Two run modes

**Mode A — loopback multi-process (primary loop).**
One server process + one or two client processes as separate `--headless` Godot
instances communicating over loopback ENet. Identical code path to a real LAN
game — no simulation-fidelity gap. Oracles use **small tolerances** rather than
exact equality because timing jitter is real, but divergences from actual bugs
are large enough that this is never ambiguous in practice. This is the primary
mode for all reproduce / diagnose / fix / confirm iteration.

**Mode B — chaos / latency (confirmation for timing bugs).**
Same as Mode A with injected latency, jitter, and packet loss via `tc netem`
or equivalent. Catches ordering, reliability, and lag-recovery bugs that only
manifest under adverse conditions. The agent runs Mode B only after a fix
passes Mode A, to confirm timing survival.

---

## 3. Snapshot schema

The backbone. Every process writes one JSON object per physics tick per tracked
entity to its own file (`server.jsonl`, `client_1.jsonl`, `client_2.jsonl`).
JSONL because it is append-only, crash-safe, and trivially parsed.

```
{
  "tick": 412,
  "wall_ms": 6840,
  "peer": 1,
  "role": "client",
  "mech_id": "slip_0",
  "pos": [12.40, 0.00, -8.13],
  "rot_local":  [0.0, 0.7071, 0.0, 0.7071],   // synced node's LOCAL transform
  "rot_global": [0.0, 0.3827, 0.0, 0.9239],   // resolved GLOBAL transform
  "health": 740,
  "ammo": {"hp_left": 3, "hp_right": 8},
  "lock_target": "cesh_2",
  "team": 0,
  "abilities": {"jump": 12.0}                  // cooldown remaining
}
```

Plus a separate event stream (same file or `*.events.jsonl`):
`{tick, peer, type, mech_id, payload, rpc_seq}` for fired / hit / captured /
died / spawned / ability, each carrying an **RPC sequence number** so dropped or
reordered RPCs are detectable.

**Critical detail tied to your known caveat:** log **both** `rot_local` and
`rot_global`. `MultiplayerSynchronizer` syncs the *local* transform, and your
torso/legs are decoupled — rotation lives on a child node. The bug where the
synced node is correct but the resolved global facing is wrong only shows if you
capture both. This is the single most likely transform desync source.

**Invariant hygiene (V5, V13, V16):** logging is the one place runtime GDScript
gets added, since a Python tool cannot read live game state. Keep it minimal,
route it through `Game.gd` (e.g. `Game.sync_log(...)`) — **not a new autoload** —
gate it behind a flag (`--sync-log` / `Game.sync_logging_enabled`) so it is
zero-cost off and removable, hyphens-only in comments, and commit it **separately**
from any fix. All comparison and oracle logic lives in `tools/*.py`.

---

## 4. Oracle library and scope manifest

`tools/oracles/*.py`. Each oracle takes the three logs plus the scenario spec and
returns a verdict:

```
{
  "oracle": "transform_desync",
  "verdict": "FAIL",
  "pattern": "accumulating_drift",    // constant_offset | accumulating_drift | sudden_jump | none
  "mech_id": "slip_0",
  "first_tick": 388,
  "magnitude": 2.74,
  "field": "rot_global",
  "note": "client_1 vs server, grows ~0.02 rad/tick from tick 388"
}
```

**In scope (log-detectable, agent may attempt fixes):**

| Oracle | What it checks | Example pass criterion |
|---|---|---|
| `determinism` | two identical runs match | epsilon-identical tick streams |
| `transform_desync` | pos + rot_local + rot_global vs server | divergence < epsilon for > N ticks |
| `health_desync` | HP per mech vs server | matches within latency window |
| `beacon_desync` | ownership + capture progress | exact match per tick |
| `ammo_desync` | mag / reload state | client prediction reconciles, no permanent gap |
| `spawn_join` | late-joiner's first snapshot vs server same-tick | per-mech match at join tick (catches constant_offset) |
| `prediction_recon` | correction magnitude per tick | no oscillation; large single corrections flagged |
| `event_sidefx` | correlate event stream with sudden_jump | every jump has a matching replicated event |
| `team_assignment` | team + same-team damage skips (V-friendly-fire) | no cross-team-state leak; matches B27 |
| `lock_target` | locked_target vs server; dead bodies unlockable | match; no lock on dead (B21/B23) |
| `rpc_integrity` | rpc_seq gaps / reorders | monotonic per channel |
| `latency_recovery` (Mode B) | converges after disturbance ends | back below epsilon within recovery window |
| `crash_scan` | stderr + exit codes | no push_error, no nonzero exit, no process death (catches B17-class) |

**Out of scope (route to a `NEEDS_HUMAN.md` list, never attempt):**
rendered-position smoothing that does not appear in transform logs; input feel /
perceived rubber-banding within tolerance; audio sync; animation phase that does
not affect gameplay transforms. If an oracle is green but you later report a
visual symptom, that is this bucket — flag and stop, per the original stop
condition.

---

## 5. Scenario suite

Declarative scenario files (`tools/scenarios/*.json`), each a reusable regression
test, each targeting a bug class:

```
{
  "name": "rotation_decoupled_torso",
  "mode": "loopback",
  "seed": 1337,
  "duration_ticks": 600,
  "peers": {"server": {}, "client_1": {"input": "strafe_and_turn.inputs"},
            "client_2": {"input": "hold.inputs"}},
  "latency_ms": 0,
  "oracles": ["transform_desync", "event_sidefx"],
  "thresholds": {"rot_epsilon": 0.01, "persist_ticks": 5}
}
```

Author one scenario per in-scope class above. The suite doubles as your
permanent multiplayer regression net: any future netcode change reruns it.
Running the full suite after every accepted fix is how the agent catches
regressions without you.

---

## 6. The agentic loop and guardrails

A top-level Claude Code brief drives a **work queue** (known + suspected bugs:
the transform caveat, B21/B22/B23 lock issues under net, B27 friendly fire under
net, plus anything the suite flags red). The agent works the queue one item at a
time:

1. **Reproduce.** Run the item's scenario in Mode A. Confirm a FAIL verdict. If
   it passes, mark NOT-REPRODUCIBLE and move on.
2. **Diagnose.** Read the oracle's pattern + first_tick + field, then read only
   the relevant code paths. The pattern *is* the diagnostic lead: constant offset
   → spawn/join; accumulating drift → prediction/correction; sudden jump → an
   event with an unsynced side-effect.
3. **Hypothesize + patch.** Smallest change that addresses the diagnosis.
4. **Confirm.** Rerun the scenario (Mode A loopback), then Mode B (chaos) for timing survival.
5. **Regression.** Run the full suite. If anything went red, revert the patch.
6. **Commit.** One commit per confirmed fix: bug ID, oracle now green, one-line
   rationale. Frequent commits = easy rollback.

**Guardrails (these are what make "forget it" safe):**

- **3-strikes per item.** Three *distinct* failed approaches → mark BLOCKED,
  write findings to the journal, move to the next item. Never loop on one bug.
  (Your standing rule, SPEC §C, applied strictly to autonomy.)
- **Change budget.** Touch only files relevant to the current item. No refactors,
  no "while I'm here." Hard-respect §V1–V19 (no 4th autoload, no renderer change,
  no `depth_test_disabled`, untyped loadout access, seeded RNG, hyphen comments).
- **Global stop conditions.** If a fix breaks the determinism baseline → revert,
  BLOCK that item. If the build won't compile → revert to last green; if it still
  won't, halt the whole run and journal. If more than ~20% of the suite goes red
  after a change → revert it.
- **Instrumentation is separate.** Logging commits land first and are never mixed
  with fix commits.
- **Run journal** (`AUTODEBUG_JOURNAL.md`, append-only): per item — hypotheses,
  diffs, verdicts, commit hashes, BLOCKED reasons. This is what you read when you
  return. End-of-run summary at the top.

---

## 7. Front-loaded approvals (one-time sign-off, then hands-off)

These are the only decisions that need you. Approve once and the run needs zero
interaction:

1. **Permission allow-list.** Pre-configure Claude Code so it never prompts
   mid-run: allow edit/write within the repo, allow the harness scripts and
   `godot --headless ...`, allow `git add` / `git commit`. (Exact settings file
   name and non-interactive flags shift between Claude Code versions — pin them
   against current `claude` docs rather than from memory; the *mechanism* is a
   settings allow-list plus a non-interactive invocation.)
2. **Dependencies pre-installed.** Nothing fetched mid-run. Install the Python
   deps for the comparison/oracle tools via aptitude before starting (I'll list
   packages when we build M1; you run aptitude separately).
3. **Push policy.** Recommend **commit but do not push** — autonomous commits are
   safe and reversible, pushing is a publish action and your repo stays private.
   Override to allow push is one allow-list line if you want it.
4. **Scope manifest sign-off.** Confirm the in/out-of-scope split in §4 so the
   agent never wanders into feel/visual territory.
5. **Determinism baseline green.** Do not unleash M3 until the §1 self-test
   passes. This is the natural checkpoint where you glance once, then walk away.

---

## 8. Phasing (maps to fresh Claude Code sessions)

- **M0 — Determinism + instrumentation foundation.** `ReplayInputSource`, seeded
  RNG audit, two-process headless loopback mode, flagged JSONL logging through
  `Game.gd`, determinism self-test. *Deliverable:* green baseline + clean logs
  from one canned scenario. Your one checkpoint.
- **M1 — Comparison + oracle library.** `tools/sync_compare.py` + oracle modules
  + verdict format. *Deliverable:* run a scenario, get machine-readable
  PASS/FAIL + diagnosis.
- **M2 — Scenario suite.** One scenario per in-scope class. *Deliverable:* the
  full regression net runs end-to-end and reports.
- **M3 — Agentic loop + guardrails + permission front-load.** The driving brief,
  change budget, 3-strikes, stop conditions, commit discipline, journal,
  allow-list. *Deliverable:* hand it the queue, walk away.
- **M4 — Latency / chaos suite (Mode B).** `tc netem` jitter / loss / latency
  injection + convergence oracles. *Deliverable:* coverage of timing-class bugs
  Mode A loopback cannot reliably surface.

M0–M2 are buildable now. M3 has bugs to chew on once netcode is generating
divergence. Sonnet for M0–M2 (mechanical/build-out), Opus for the M3 brief design.
