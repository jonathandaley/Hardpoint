# NEEDS_HUMAN.md -- things the agent can't decide (feel, taste, design)

Each entry: date | task | what to look at | where | why the agent stopped.
Delete an entry once you've answered it (or answer inline and the agent will act).

- 2026-11-02 | T184/T200 | CORRECTION: the suite is isolated (harness + probes run with their own XDG_DATA_HOME under build/suite_runs/). What touched your real user://profile.cfg was Claude running probes directly by hand (T183-T185 debugging): ~4 test losses since 20:20 -- now 0 W / 4 L, ELO 980, XP 111, level 2, coins 100. The pre-session values are unknown, so nothing was restored; say what to reset it to (or delete profile.cfg for a fresh profile). Manual runs now use a scratch XDG_DATA_HOME. | ~/.local/share/godot/app_userdata/Hardpoint/profile.cfg | your data, your call
