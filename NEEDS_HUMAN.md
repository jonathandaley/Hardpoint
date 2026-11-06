# NEEDS_HUMAN.md -- things the agent can't decide (feel, taste, design)

Each entry: date | task | what to look at | where | why the agent stopped.
Delete an entry once you've answered it (or answer inline and the agent will act).

- 2026-11-03 | T209 | First balance baseline (32 all-bot Elite matches, 672 mech lives; full table in build/balance/balance_20261103_150259.md, rerun any time with `python3 tools/balance_eval.py -n 32`). No mech or weapon is shown to be off: every win rate sits at 38-58% with overlapping 95% ranges (lowest Pegasus 38% (28-49), highest Hornet 58% (47-68)). Worth a look: ARC and ROCKET deal far less damage per life (129 and 106) than the rest (300-650) and lose 2.5-3x more than they deal -- either the weapons are weak or the bots use them badly (rockets need a lock; the arc is short range); SNIPER and SHOTGUN deal the most damage but win no more often. More matches (-n 100) would narrow the ranges. | tools/balance_eval.py | balance changes are your call (report only)

- 2026-11-05 | T262 | MG barrel glow: the barrel + muzzle get a dull red glow that brightens to red-hot orange as the fire rate ramps, then cools after you let go. Not seen by eye: colours are GLOW_COOL / GLOW_HOT in MachineGun.gd; if it sits off the barrel on some mech, say which. | scripts/MachineGun.gd | look call
