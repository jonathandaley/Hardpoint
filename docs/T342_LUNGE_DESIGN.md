# T342 Taurus lunge -- design draft

Ability resource: effect_key "lunge", trigger ACTIVE, duration 0 (cooldown starts at press), cooldown 5.5 s.

## Mech.gd
consts (calibration knobs): LUNGE_WINDUP_S 0.2, LUNGE_DASH_S 2.0, LUNGE_STOP_S 0.25,
LUNGE_PEAK 10.0 m/s, LUNGE_RAMP_S 0.8, RAM_FLOOR 60, RAM_K 9 per m/s closing speed.
state: lunge_t (-1 idle), _lunge_dir, _lunge_hit {}, _lunge_stop_t (-1 or time stop began).
lunge_speed(t): 0 in windup; PEAK * min(1, (t-W)/RAMP)^2 in dash; decel linear over STOP_S from
the speed at stop. Stop triggers: dash time over, ram, wall.
_handle_movement: if lunge_t >= 0 -> velocity.xz = _lunge_dir * lunge_speed, no input steering;
tick lunge_t += delta (fixed physics delta -> deterministic). Gravity still applies.
After _slide (server only): for each slide collision during the dash: mech (enemy) not in
_lunge_hit -> ram damage max(RAM_FLOOR, RAM_K * closing) via request_damage(amount, self)
(source self: no `damage` prop -> clamp skipped), then stop. PhysicalShield collider -> its
take_damage(amount) (Everest front shield takes it), stop. Static with normal.dot(-dir) > 0.6 -> stop.
Activation: _activate_ability "lunge": _lunge_begin(dir = torso forward flattened).
RPC _rpc_ability_activated(slot) -> add args? NO signature change for others: new RPC
_rpc_lunge(seq, tick_n, dir) "authority" reliable call_remote: non-owners start visuals at t=0;
owner (predicting) finds (seq, n) in _pred_hist -> lunge_t = elapsed ticks / 60, adds the missed
displacement (sum of lunge_speed over the missed ticks) to position + later hist records.
Snapshot: none needed (interp moves non-owners; lunge visuals from the RPC).

## Visuals (every peer)
BipedLegs.update_gait(..., airborne, lunge_pose) with lunge_pose = Vector2(crouch 0..1, stride 0..1):
crouch = windup blend (knees bend 0.9, hips +0.5, torso y -0.22*crouch), stride = dash: hip sweep x1.8,
cycle rate from real speed. Recovery = blend out at AIR_BLEND.
Glow: emissive mats on the mech scaled 1 + 2.5 * speed/PEAK (find E materials once; restore at end).

## Bots (AIInputSource._use_abilities, tactics only like the others)
"lunge": has target, 6 m < dist < 16 m, |angle_h| < 0.12 rad, ray from chest along facing to the
target hits the target (no wall), not low HP retreat. Press.

## Probes
lunge: SP arena, Taurus vs a dummy 10 m ahead: windup no movement, dash curve distance within
tolerance of the analytic integral, ram damage >= floor once, stops; wall stop no damage;
cooldown blocks a second press. Bot press. Legs pose crouch during windup (knee angles).
MP: scenario with a Taurus player lunging (owner prediction error small) -- check existing
scenario framework for ability presses (jump_heal scenario?) + --net wifi,bad sweep.

## Confirmed while reading (2026-11-09)
- Physics order (server, Mech._physics_process_impl): _handle_movement -> ... -> _handle_ability
  (activation) -> _slide -> input_ack_ticks += 1 -> _update_legs. So at the activation tick the
  owner's matching prediction record is (seq = input_ack, n = input_ack_ticks + 1); the server's
  first lunge displacement happens on the NEXT tick, i.e. the owner's record idx + 1 uses lunge_t = dt.
- Owner catch-up on the RPC: find record (seq, n) in _pred_hist (scan back, stop at older seq);
  elapsed = hist.size() - 1 - idx; rewrite records idx+1.. horizontally to base + cumulative
  dir * lunge_speed(j*dt) * dt (keep y), set global_position to the last; lunge_t = elapsed * dt.
  Not found -> start now, reconcile eases the rest.
- Non-owner clients: no physics (snapshot interp, V38) -> tick the lunge clock in the interp branch
  for the pose / glow only, starting at -INTERP_DELAY (0.15 s) so the crouch lines up with the
  interpolated motion.
- Ram source = the Taurus mech itself: request_damage's clamp reads `damage` / `range` only if
  the source has them (a Mech has neither) -> passes; _owning_mech(self) = self -> kill credit.
- PhysicalShield.take_damage(amount, src) exists -> collider.has_method("take_damage") covers
  mech + front shield; owner mech via _owning_mech(collider).
- Glow: MechVisuals glow materials are SHARED per palette (static _speckles cache) -> duplicate
  this mech's emissive overrides once on its first lunge before scaling emission_energy_multiplier.
- Kit legs use BipedLegs; update_gait(velocity, basis, rot_speed, walk_speed, delta, airborne)
  -> add lunge pose arg (crouch, stride). The torso carries the camera arm, so no torso pitch
  lean (camera change is out of scope): crouch = knees + hips + torso y dip only.
- Speeds in absolute m/s (Taurus walks 0.9 m/s): ramp to 10 m/s over 0.8 s then hold to 2.0 s
  (~15 m), 0.25 s stop. RAM_FLOOR 60 (~1/3 of a 175 HP light), RAM_K 9 per m/s (~90 at full).
- Bots: _use_abilities is tactics-only (Hard/Elite), like jump_heal / stealth.
- MP scenario: tools/scenarios/*.json takes "mech" (Taurus.tres) + ability pulses; oracles
  transform_desync / pred error + the --net wifi,bad sweep.
