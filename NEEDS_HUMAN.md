# NEEDS_HUMAN.md -- things the agent can't decide (feel, taste, design)

Each entry: date | task | what to look at | where | why the agent stopped.
Delete an entry once you've answered it (or answer inline and the agent will act).

- 2026-11-02 | T184 | Test runs write the real profile: the MP harness (and now SP probes like sp_match_end) end matches through Game._update_mp_profile, which saves user://profile.cfg -- the same file the game uses when run from this project on this machine (it was rewritten during today's suites; current values look like test residue: 0 W / 1 L, ELO 983). Decide whether tests should use a separate user dir (project setting use_custom_user_dir / a --test flag that skips save_profile). | autoloads/Game.gd save_profile | needs a call on how test isolation should work
