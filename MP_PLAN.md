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

## Phase 6 -- deferred

- Late-join / spectate: `Match.gd:46-50` in-progress state sync. Out of scope until 1v1 / co-op stable.

## Order rationale

P0 invariants → P1 bugs → P2 architecture → P3 determinism → P4 wiring → P5 measure-then-opt.
Each prior phase makes next safer:
- P0 invariants → `/check` drift detection live before code change
- P1 bugs → no spurious failures masked by stale-ref crashes
- P2 chokepoints → P4 has single seam to attach @rpc
- P3 determinism → P4 RNG sync trivial
- P4 wiring → P5 bench measures real MP load, not SP

Skipping P0 = future drift unchecked. Skipping P2 = P4 touches every fire callsite individually.

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

## Cross-ref

SPEC.md owns:
- Invariants V22-V34
- Tasks T92-T108
- Bug B28

This file owns:
- Phase ordering + dependencies
- Risk table + rollback
- T106 gating logic
- Rejected-from-audit list
