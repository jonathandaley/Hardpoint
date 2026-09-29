# T129 LAN test checklist

Human 2-peer LAN session. Passing closes T40 (SPEC.md). First session 2026-09-28; both machines on Godot 4.6.2, both windows at the default resolution.

## Passed

- [x] Health bars visible on both server and client. The open "server bar missing on client" bug is resolved.
- [x] Hit indicator is correct on the client and lights when the server registers a hit. Both players see the health drop.
- [x] Reload bar (client): correct
- [x] Ammo counter (client): correct
- [x] Reloading works
- [x] #25: a client that leaves mid-match turns into a bot
- [x] Shotgun: as accurate as the other weapons (so it has the same B-a drift, nothing extra)
- [x] Weapon effects consistent between server and client (#8 rockets, #10 machine gun, #15 raycast/laser/arc/shotgun, #20 aerial strike). The laser and arc weapon have aim problems of their own, listed below.

## Bugs found

### B-a: client aim drifts off over time (server aim is fine)
- Accurate at match start, then drifts later on.
- The client's shots look correct on the client's own screen, but the server's result is off by a few degrees.
- The offset looks roughly constant at any one moment but isn't the same from moment to moment. The tester suspects "rotation being calculated differently" between the peers.
- Lead: something rotation-related accumulates differently on client vs server, so the client's aim point or basis desyncs from the server's copy. Not yet traced. See memory feedback_weapon_aim_pattern (the aim point must come from a camera raycast).

### B-b: laser misses even on the client's own screen
- The only weapon that looks wrong from the client's own perspective. May be the same root cause as B-a but showing up locally because the laser's visual comes from server state (`_rpc_beam_fx`).

### B-c: client arc weapon stays locked on too long / too far off-angle
- Keeps its lock while the target is well outside the aim cone.
- Not checked whether the server does the same.

### B-d: client weapon HUD icons are squashed together at the bottom of the screen
- Client only. Both windows at the default resolution, so a different window size isn't the cause.
- Wrong from spawn.
- Toggling weapons changes how the squashed icons look, erratically. Firing is unaffected, and the reload bar and ammo counter render correctly.

### B-e: red aiming box
- The client never gets the red aiming box (the square aim indicator) when flying a mech with only rifles and no lock-on weapons.
- With a lock-on weapon, the lock-on ring does add the red box.
- The tester is "pretty sure" but wants it rechecked. Possibly the box is only drawn when a lock weapon is present, or only on the server for non-lock loadouts.

### B-f: no way back to the lobby after quitting
- Quitting a match returns to the hangar, and there is no way back into the waiting room (lobby).

### B-g: log flood after the client quits (client log)
- Endless `Node not found: "Arena"` / `"Arena/BeaconMatch"` + `Failed to get cached node from peer 1` + `Invalid packet received`, several per second.
- Cause (read from code, not yet proven): `Arena._on_pause_quit` (Arena.gd ~3165) just changes scene to the hangar. It never closes `multiplayer.multiplayer_peer`, so the client stays connected and the server keeps sending `_rpc_snapshot` (20Hz) and BeaconMatch RPCs to an Arena the client no longer has. The HUD's end-of-match "RETURN TO HANGAR" button (HUD.gd:293) has the same shape.
- Probably the same root as B-f: the client is half-left (out of the scene, still a connected peer), so the lobby flow never restarts. Fix both together: quitting should leave the session cleanly (close the peer, or explicitly return to the lobby).
- Worth confirming how #25's bot-ify was triggered, since the peer apparently didn't disconnect.

### B-h: `receive_snapshot` on a mech outside the tree (client log)
- `Condition "!is_inside_tree()"` from `get_global_transform`, via `Mech.receive_snapshot` (Mech.gd:417) <- `Arena._rpc_snapshot` (Arena.gd:3544).
- `entry.get("quat", global_transform...)` evaluates its default argument eagerly, even when "quat" is present, so any snapshot for a valid-but-detached mech (dead or removed) errors. `_rpc_snapshot` only checks `is_instance_valid`, not `is_inside_tree`.
- Low severity (noise), but it trips `crash_scan` (V46), so it will fail a suite run if a scenario ever hits it.

### Server log
- "Much the same", plus MovementLogger output and other noise. Not captured in detail; grab it next session if the server shows anything different from B-g and B-h.

## Still to test

- [ ] B-e: recheck that the red box is missing for an all-rifle client mech, and whether the server shows it for the same loadout
- [ ] B-c: does the server's arc weapon over-hold its lock too?
- [ ] Weapon icon dims when it can't fire (blocked by B-d)
- [ ] Overall feel: stutter, rubber-banding (decides whether T131 prediction is needed)
- [ ] #21: in 5v5, bots on both teams target the correct beacons

## After T129

File each bug via backprop (SPEC.md §B), one fix per session. Suggested order: B-a (may also explain B-b and B-c), then B-f+B-g together, B-d, B-e, B-h (small). Then G24-G27.
