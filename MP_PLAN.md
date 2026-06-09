# MP_PLAN

Multiplayer-readiness plan. Companion to SPEC.md (canonical). This file = phase order, risk, rollback, gates, rationale. SPEC owns invariants (V22-V34) + tasks (T92-T108).

## Principle

Each phase = behavior-preserving refactor first, switch flip second. Invariants land before refactors so `/check` catches drift. Bench before/after every change in `_physics_process`. ⊥ deletes -- wrap, don't replace.

## What this plan deliberately does NOT do

- ⊥ delete current code; all wrapped, not replaced
- ⊥ mass perf opts; T106-T108 only, gated on measurement
- ⊥ remove `get_nodes_in_group` from lock/splash; needed at current scale, not a real cost
- ⊥ pin tick-rate; SP works w/ variable delta
- ⊥ HUD optimization; scales fine ≤16 mechs
- ⊥ late-join / spectate; deferred (P6, post-MP-stable)

## Phase map

| Phase | Tasks | Goal | Risk | Rollback |
|-------|-------|------|------|----------|
| P0 | T92 | Codify current behavior; baseline drift | none | n/a |
| P1 | T93, T94 | Real bug fixes (SP+MP win) | low | per-task revert |
| P2 | T95, T96, T97 | Routing chokepoints; no behavior change | low | per-task revert |
| P3 | T98, T99 | Determinism prep; cosmetic RNG tagged | low | per-task revert |
| P4 | T100-T105 | Replication wiring; MP flips on incrementally | medium | per-task revert; SP fallback when single-peer |
| P5 | T106-T108 | Perf pooling; gated on T106 measurement | low | revert pool |
| P6 | -- | Late-join/spectate; out of scope this batch | -- | -- |
| P7 | T109, T110 | Transport core + MP entry UI | low | revert; SP path untouched |
| P8 | T111-T114 | Lobby state + per-peer squad/ready | medium | revert lobby scene; SP path untouched |
| P9 | T115, T116, T121 | Match lifecycle RPCs (start/end/scene change) | medium | per-task revert; SP path untouched |
| P10 | T117-T120 | Per-peer simulation (input, snapshot, client gating) | high | per-task revert; SP path untouched |
| P11 | T122 | HUD multi-peer perspective; unblocks T65 | low | revert |
| P12 | T123-T125 | Disconnect + sender validation + rate-limit | low | per-task revert |
| P13 | T126 | MP ELO/XP/coins integration | low | revert |
| P14 | T127, T128 | Squad-of-5 lives in MP | medium | per-task revert |
| P15 | T129 | LAN smoke + bench gate | none | n/a (gate) |
| P16 | T130-T132 | Dedicated build, prediction, late-join (deferred) | -- | -- |

## Phase 0 -- lock current behavior

Goal: capture today's working contract before touching anything.

- T92 establishes V22-V26 (already in §V).
- Run `/check`. Expect violations from existing code (e.g. `randf` in AIInputSource, inline node creation in VFX, direct `Input.*` reads).
- Catalog as drift baseline. ⊥ pre-fix in T92.

Verification: SP gameplay unchanged ∴ no risk.

## Phase 1 -- real bugs

Goal: fix bugs that exist today regardless of MP. Both fixes also unblock MP.

- T93: Beacon `_capturers` stale ref guard. Reproducible SP (kill mech mid-capture → ghost progress). Logged as B28.
- T94: defensive `is_instance_valid` on cached refs. ⊥ behavior change when refs valid; null-skip when stale. Effect = no crashes when ref freed.

Verification: kill mech mid-capture → no ghost progress. Crash-bench arena (rapid spawn/free) → no `null` errors.

## Phase 2 -- routing centralization

Goal: make MP wiring a one-line flip later. Behavior identical SP.

- T95: weapon fire chokepoint `Mech.fire_weapon(slot, aim)` wraps scattered paths.
- T96: damage chokepoint `Mech.request_damage(amount, source)` wraps `_apply_damage`. ⊥ clamp yet (T103).
- T97: VFX/SFX broadcast hook -- optional `broadcast: bool = false` param. Unused SP.

Verification: full SP smoke run; frame-time delta <1%; weapons fire/hit/sound identical.

## Phase 3 -- determinism prep

Goal: seed RNG; cosmetic stuff stays cosmetic.

- T98: `AIInputSource` swap to seeded `RandomNumberGenerator`. SP seed = time-based for variance (bots feel same). MP seed deferred to T104.
- T99: tag cosmetic RNG (`# cosmetic`) -- pod ejection, VFX particle spread. Cosmetic keeps global `randf`; differs per peer in MP, no game-state cost.

Verification: 5-match SP run, bot behavior subjectively unchanged.

## Phase 4 -- replication wiring

Goal: flip switches one system at a time. Each = revertible. SP fallback required (single-peer detected → no RPC overhead).

- T100: projectile spawn RPC; server-authoritative collision; client = visual ghost.
- T101: weapon fire RPC broadcast (audio/VFX). Flip `broadcast=true` from T97.
- T102: lock state sync via id, not Node ref.
- T103: server-side damage validation in `request_damage`; clamp + range gate.
- T104: bot RNG deterministic seed broadcast at match start.
- T105: beacon capture progress periodic RPC.

Verification per task: 2-peer LAN test before merging next. SP path tested after each (single-peer must still work).

## Phase 5 -- perf (gated)

Goal: ⊥ premature opt. Only fix what bench shows.

- T106: bench arena under sustained fire (4 bots vs player, 30s). Frame-time histogram. Profile via Godot profiler.
  - If stable <16ms 99th pct → SKIP T107/T108. Mark in §B as "tried, no win needed".
  - If hitches → identify top source from profiler.
- T107 (conditional): VFX pool for top hitch source only.
- T108 (conditional): SoundManager `AudioStreamPlayer3D` pool.

Verification: before/after frame-time histogram. ⊥ improvement → revert pool.

## Phase 6 -- deferred (mid-batch)

- Late-join / spectate of in-progress matches: superseded by T132 below; same intent, now scheduled in P16.

## Phase 7 -- transport + entry

Goal: wire ENet through Godot's MultiplayerAPI; surface host/join in the menu. ⊥ touch SP path.

- T109: `Game.gd` networking core. `host()`, `join()`, `disconnect()`, signals. Folded into `Game.gd` per V5 (⊥ new autoload).
- T110: TitleScreen "Multiplayer" button → `scenes/ui/MPEntry.tscn` (host/join IP form) → Lobby on success.

Verification: host on one machine, join on another, both reach an empty Lobby scene; SP path identical when no peer attached.

## Phase 8 -- lobby

Goal: server-authoritative lobby (V39) with replicated state to clients; per-peer squad picker. ⊥ behavior change to Hangar single-player flow.

- T111: Lobby scene + `Game.mp_lobby` server-authoritative dict.
- T112: Peer profile metadata RPC (pilot_name, ELO, level) -- foundation for V36.
- T113: Per-peer squad RPC -- shrunken Hangar widget embedded; server validates squad shape + slot fit (V17).
- T114: Ready toggle RPC; host start-button gated.

Verification: host + 1 join, both see each other's metadata + squad summaries; host alone cannot start without bot-fill enabled.

## Phase 9 -- match lifecycle

Goal: server drives Hangar→Lobby→Arena→Lobby scene flow (V40). Each transition = one RPC.

- T115: Match-start RPC -- builds final roster including bot-fill (T104 seed reuse), broadcasts, all peers `change_scene_to_file`.
- T116: Arena reads broadcast roster + spawns per-peer mechs with `owner_peer_id` (V35); assigns input sources by ownership.
- T121: Match-end RPC + return-to-lobby; `_rpc_change_scene(Lobby)` after all confirm.

Verification: host + 1 join, host starts a match, both peers load Arena with correct mech roster and team colors, match ends, both peers return to Lobby with state preserved.

## Phase 10 -- per-peer simulation

Goal: actual gameplay across the wire. This is the highest-risk phase; each task individually revertible. ⊥ delete SP path; client gating switches on only when peer attached.

- T117: `NetworkInputSource` -- new InputSource subclass, server-only.
- T118: Client input forwarding RPC (30Hz) + server applies to peer's NetworkInputSource.
- T119: Mech transform snapshot RPC (20Hz) + interpolation buffer; shield/ability event RPCs round out state sync.
- T120: Client-side gating in `Mech._physics_process` (V38); ⊥ direct simulation on non-server peer.

Verification: host + 1 join, remote peer's mech walks/turns/fires/takes damage visibly identical to host's view (modulo interpolation lag); host's local mech feels unchanged from SP.

## Phase 11 -- HUD / perspective

Goal: HUD reads correctly from any peer's POV. Closes long-standing T65.

- T122: Local team always blue, enemy always red; scoreboard with pilot_name + ELO + per-peer stats.

Verification: host sees self blue + remote red; remote peer sees self blue + host red. Beacon dots match.

## Phase 12 -- robustness

Goal: don't crash on disconnect; reject malformed clients; rate-limit input.

- T123: Peer-disconnect mid-match → swap to bot AIInputSource; match continues.
- T124: Audit + add sender validation to every `@rpc("any_peer")` (V41).
- T125: Server input rate-limit (60Hz cap per peer).

Verification: kill a client process mid-match; host's match continues, that peer's mech goes bot-controlled. Hand-crafted bad RPC from a peer (manual `rpc_id`) drops at the handler with `push_error`.

## Phase 13 -- persistence

Goal: ELO/XP/coins update from MP results, locally per peer (V36).

- T126: Each peer applies own ELO + XP + coins on `_rpc_match_end` using broadcast pre_elo array.

Verification: run two matches end-to-end; ELO on each peer moves the expected direction; profile.cfg persists across restart.

## Phase 14 -- squad lives in MP

Goal: T64 squad-of-5 works for every peer.

- T127: Per-peer next-mech picker on death; `_rpc_pick_next_mech` server-validated.
- T128: Spectate fallback when own squad exhausted (T58 reused).

Verification: 1v1 match with bot-fill; both players cycle through full 5-mech squads; final-elimination triggers match-end correctly.

## Phase 15 -- LAN smoke + bench gate

Goal: prove the system works end-to-end before opening up to dedicated/prediction work.

- T129: 2-peer LAN run, 10min beacon drain, verify capture-progress, kills, damage, ELO update, disconnect resilience, no errors, frame-time stable.
- The T129 session should also pick up the open MP batch in AUDIT_PROGRESS.md (#10, #11, #15, #16, #27, #28) and verify the batch-1 fixes tagged [needs MP test] there (#8, #21, #25) -- same running match covers all of it.

Gate: P16 work begins only after T129 passes. If T129 shows interpolation feel is unacceptable on LAN → T131 unblocked.

## Phase 16 -- deferred future work

Out of scope this batch. Tracked here so they don't surprise.

- T130: Dedicated server build (`--server` flag). Same code path, no local PlayerInputSource at match start (V35). Wait for T129.
- T131: Client-side prediction for own mech. Only if T129 LAN test shows interpolation lag is unacceptable. Most expensive task in the batch.
- T132: Reconnect / late-join. Slot reservation + spectate-only reconnect. Wait until first-round MP feedback shows demand.

## Order rationale (extended)

P0→P5 = behavior preserved while authority seams take shape (already complete).
P6 = explicit out-of-scope mid-batch.
P7 = transport/UI is the cheapest place to break things; do first.
P8 = lobby in isolation, no Arena entanglement yet.
P9 = scene-flow + roster spawn before any wire-level gameplay; lets P10 land into a known shape.
P10 = the actual gameplay-across-wire; gated by P9 having a working scene transition.
P11 = HUD perspective once mechs exist on both peers.
P12 = robustness once happy-path works.
P13 = persistence layer on top of working match.
P14 = squad-of-5 (also touches SP via T64; do not let MP needs degrade SP feel).
P15 = gate. The point at which T40 closes.
P16 = deferred enhancements.

## What this MP batch deliberately does NOT do

Carries forward from earlier batch + adds:
- ⊥ central account backend (V36; T75 stays deferred)
- ⊥ NAT punch / matchmaking service / relay (direct-IP LAN/friend only)
- ⊥ client-side prediction for own mech first cut (V37; T131 if needed)
- ⊥ reconnect during match (T132 future)
- ⊥ chat / voice (out of scope, no task created)
- ⊥ cosmetic asset sync mid-match (cosmetics local; sync at lobby join only)
- ⊥ anti-cheat beyond rate-limit + sender validation (V41 + T125 are the floor)

## Cross-ref (extended)

SPEC.md owns:
- Invariants V22-V34 (prior batch) + V35-V41 (this batch)
- Tasks T92-T108 (prior) + T109-T132 (this)
- §C MP-architecture bullets (hosting, accounts, transport, movement, bot-fill)

This file owns:
- Phase ordering + dependencies (P0-P16)
- Risk + rollback table
- T106 gating logic
- T129 LAN smoke gate logic for P16
- Rejected-from-audit list (still applies)
- This batch's explicit non-goals

## Rejected from audit (kept for record)

These flagged in initial audit, rejected as bogus or not worth fixing:

- Lock cone scans all mechs/frame (`Mech.gd:497-514`) -- needed; ⊥ avoidable; ~8 mechs = trivial cost
- Step-up double raycast/tick (`Mech.gd:365-417`) -- 2 raycasts = nothing
- Stealth recursive mesh walk (`Mech.gd:579`) -- toggle-only, not per-frame
- Beacon `_teams_present()` per-tick -- O(24) ops, trivial
- HUD `unproject_position()` spam -- scales fine ≤16 mechs
- HUD ability label rebuild/frame -- minor string alloc
- Tick-rate not pinned -- SP works w/ variable delta; MP problem if measured

If bench (T106) shows any of these as real hitches, revisit.
