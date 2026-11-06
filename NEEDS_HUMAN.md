# NEEDS_HUMAN.md -- things the agent can't decide (feel, taste, design)

Each entry: date | task | what to look at | where | why the agent stopped.
Delete an entry once you've answered it (or answer inline and the agent will act).


- 2026-11-03 | T209 | First balance baseline (32 all-bot Elite matches, 672 mech lives; full table in build/balance/balance_20261103_150259.md, rerun any time with `python3 tools/balance_eval.py -n 32`). No mech or weapon is shown to be off: every win rate sits at 38-58% with overlapping 95% ranges (lowest Pegasus 38% (28-49), highest Hornet 58% (47-68)). Worth a look: ARC and ROCKET deal far less damage per life (129 and 106) than the rest (300-650) and lose 2.5-3x more than they deal -- either the weapons are weak or the bots use them badly (rockets need a lock; the arc is short range); SNIPER and SHOTGUN deal the most damage but win no more often. More matches (-n 100) would narrow the ranges. | tools/balance_eval.py | balance changes are your call (report only)
- 2026-11-04 | T235 | Corvette (the Tantive-style ship interior) is in: roofed corridors 11 m wide under a 10 m ceiling, spawn halls at the ends, a reactor room, beacon alcoves. Unreviewed by eye (display still down): wall/floor panel look, light strips, whether the corridors feel right. Gameplay note: under the roof, Aerial Strike and arcing rockets hit the ceiling (as you chose); say if Aerial Strike should be disabled or reworked indoors. Also new everywhere: the shoulder camera now keeps 0.25 m off walls (it used to sit 1 cm off and could clip). | scripts/maps/Corvette.gd, scripts/Mech.gd (CAMERA_CLEAR) | look + gameplay call
Map picker should have an indoor/outdoor menu, and match doesn't start if anybody's squad has aerial/rocket if the map is indoor. Corvette being the only indoor for now. Not sure that this is the final thing, it might end up being a bad idea to have indoor maps.

- 2026-11-04 | T238 | Slip now has a small mount (45% size) and a gun 1.8x bigger resting on it (1.73 m long). Measured, not seen (display down): check it in the hangar picker -- bigger/smaller is Slip.tres weapon_scale, mount size is MOUNT_SHRINK in tools/kit_port.py (then rerun it). | resources/mechs/Slip.tres, tools/kit_port.py | look call
Much better, now the weapons are floating a bit. Lower them slightly.


- 2026-11-05 | T259/B112 | Your grey/faint arc beam: the new lightning bolt lost its colour after any shield-hit flash on your mech (the flash resets the override material it used). Fixed by moving the colour onto the mesh. If you still see grey or invisible arcs after this, put the note back in HUMAN_FOUND -- the "sometimes invisible" part may be separate. | scripts/ArcWeapon.gd | check

- 2026-11-05 | T276 | Crosshair: the centre dot is gone and each arm is now a thin wedge -- full width (1 px + dark rim) at the outside, narrowing to a point at the centre, so the aim point is open. Not seen by eye: if it is too faint, LINE_WIDTH / LINE_LEN / GAP in Crosshair.gd. | scripts/Crosshair.gd | look call
This is better, but thin the center even more. Keep the points where they are, just thin the angles going down to it.
