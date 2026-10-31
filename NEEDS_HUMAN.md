# NEEDS_HUMAN.md -- things the agent can't decide (feel, taste, design)

Each entry: date | task | what to look at | where | why the agent stopped.
Delete an entry once you've answered it (or answer inline and the agent will act).

## 2026-10-31 | T142 | B-c: arc/rocket lock holds 42 degrees off-crosshair at normal range

- **What:** once locked, the lock is kept while the target stays inside a *hold* cone of
  `7 deg x clamp(200 m / distance, 1, 6)` (`scripts/Mech.gd` `_update_lock`, `hold_cos`).
  That is **42 deg at 33 m or closer** (most fights), 21 deg at 67 m, 7 deg at 200 m.
  Acquisition still needs 5 deg. The widening came from B22 ("close targets move faster
  across the aim arc so lock drops on minor wobble").
- **Same in single-player**, so this is tuning, not a network bug. Two MP causes that made it
  look worse on the client are fixed: B38 (server aim drifted from the client's) and B40
  (client camera sat higher/further back because client mechs lost their body_scale).
- **Decision:** keep 42 deg, or lower the cap? e.g. `clampf(..., 1.0, 3.0)` = 21 deg max.
  Tell the agent a number and it will change the constant; how it feels is your call.

## 2026-10-31 | T147 | B-d (client weapon icons squashed) did not reproduce

- **What:** the client's weapon HUD matched the server's to the pixel in every harness run: headless,
  rendered on a virtual display (screenshot: `build/suite_runs/T147_render/client_1.hud_60.png`), and with
  4 loadouts (Hippogriff rifles, Slip MG / rocket / sniper). The `hud_layout` check now guards the class.
- **Untested path:** the real Title -> MPEntry -> Lobby flow with squad weapons picked per slot (the harness
  starts the match directly). T152 will drive the real lobby; if B-d is real it should show up there.
- **No action needed now.** If you happen to see it again, a screenshot (F12 isn't wired; any screenshot tool)
  and which mech/weapons the client had would pin it immediately.
