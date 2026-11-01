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

## 2026-11-01 | T156 | screenshot review: 3 things for your eye

Rendered client screenshots (half size): [spawn](docs/review/T156/spawn.jpg),
[firing](docs/review/T156/firing.jpg), [damaged](docs/review/T156/damaged.jpg),
[dead](docs/review/T156/dead.jpg), [match end](docs/review/T156/match_end.jpg).
Everything on the checklist (`tools/scenarios/screenshot_tour.json` `_checklist`) is present and correct.
These are judgment calls, not bugs:

1. **Result table "DAMAGE" is damage *taken*, by your current mech only** (`Arena._build_mp_stats` uses
   `mech.damage_taken_total`). A reader takes "DAMAGE" as dealt; the single-player result screen shows
   DEALT and TAKEN separately. Cheapest: rename the column "DMG TAKEN". Or: track damage dealt per player.
2. **Result table "ELO" shows the rating from before the match**, not the new one or the +/- change.
3. **Low contrast on bright snow:** the weapon slot numbers (1 2 3 above the icons) almost vanish at spawn,
   and the thin white crosshair disappears against white walls (firing shot). A dark outline/shadow on both
   would fix it.

Say which you want and the loop will do it.

## 2026-10-31 | T153 | refused mid-match join gives no reason

- **What:** joining a game that is already in a match now fails cleanly (B58): the host kicks the
  joiner, who lands back on the title screen. There is no "match in progress, try after it ends" message.
- **Where:** `autoloads/Game.gd` `_on_mp_peer_connected` (kick) and `_on_mp_server_disconnected` (route).
- **Why you:** wording/flow is a UX call. Cheapest option: the host sends a one-line reason RPC
  before kicking and MPEntry shows it in its error label. Say the word and the loop will add it.

## 2026-10-31 | T147 | B-d -- RESOLVED in T166 (B54), no action needed

Root cause: fresh-import icon size (116x68 PNG forced TextureRect min size); your host had a stale import cache. Fixed. Original note kept below for history.

### (history) B-d (client weapon icons squashed) did not reproduce

- **What:** the client's weapon HUD matched the server's to the pixel in every harness run: headless,
  rendered on a virtual display (screenshot: `build/suite_runs/T147_render/client_1.hud_60.png`), and with
  4 loadouts (Hippogriff rifles, Slip MG / rocket / sniper). The `hud_layout` check now guards the class.
- **Untested path:** the real Title -> MPEntry -> Lobby flow with squad weapons picked per slot (the harness
  starts the match directly). T152 will drive the real lobby; if B-d is real it should show up there.
- **No action needed now.** If you happen to see it again, a screenshot (F12 isn't wired; any screenshot tool)
  and which mech/weapons the client had would pin it immediately.
