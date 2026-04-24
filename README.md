# MechBattle

Third-person mech arena FPS. Beacon capture win condition: hold more beacons than the enemy to drain their score to zero. Single-player vs bots; multiplayer deferred until the solo loop is fun.

Built in Godot 4.6 (Compatibility renderer / OpenGL ES 3.0), targeting low-end hardware (T3500-class). Chunky-pixel 3D: 640×360 internal, nearest-neighbor scaled to 1280×720.

---

## Running

```
build/mechbattle.x86_64
```

Linux x86_64 binary. No install. Godot editor not required to play.

---

## Controls

| Input | Action |
|---|---|
| WASD | Move |
| Mouse | Look |
| Left click | Fire all equipped weapons |
| Right click | Fire active-subset only |
| 1 / 2 / 3 / 4 | Toggle weapon slot in/out of active subset |
| R | Manual reload (fixed-magazine weapons) |
| Escape | Release mouse capture |

Weapon slots shown bottom-right. Dimmed icon = excluded from right-click subset. Ammo bar greys during reload.

---

## Mech Roster

| Mech | Class | Slots | HP | Speed | Feature |
|---|---|---|---|---|---|
| Slip | Light | 1 L | Low | Very fast | — |
| Cesh | Light | 1 L | Low | Medium | Stealth (hides HP/nametag from enemies) |
| Seeker | Light | 1 H | Low | Medium-fast | — |
| Hornet | Medium | 2 L | Medium | Fast | — |
| Hippogriff | Medium | 3 L | Medium | Medium | — |
| Pegasus | Medium | 2 L | Low | Medium | Jump + heal (Q) |
| Everest | Heavy | 2 H | High | Very slow | Physical front shield |
| Vesuvius | Heavy | 3 H | High | Slow | — |

Light (L) and Heavy (H) slots. Heavy weapons deal ~2x damage, fire slower.

DebugMech: 4x tall, invincible, 2x Slip speed. Dev use only.

---

## Document Map

| File | Purpose |
|---|---|
| `DESIGN.md` | Architecture decisions: Player/Pawn split, rendering constraints, team model, multiplayer plan. The canonical "why" doc. Read before any architectural change. |
| `SPEC.md` | Machine-readable spec: §G goal, §C constraints, §I interfaces, §V invariants, §T task list, §B bug log. Source of truth for Claude Code sessions. |
| `ROADMAP.md` | Prioritized work queue organized by phase (1–9). Includes Godot 4.6 landmines, per-task risk levels, and "what Jonathan does vs Claude." |
| `STATUS.md` | Ledger of shipped features: what's done, commit references, known issues table, and a quick file map. |

**Short version:** DESIGN = why, SPEC = rules, ROADMAP = what's next, STATUS = what shipped.

---

## Project Structure

```
autoloads/
  Game.gd           -- singleton: profile (wins/losses) + settings (sensitivity/difficulty)
  SoundManager.gd
  VFX.gd

scripts/
  Mech.gd           -- movement, step climb, fire dispatch, death, camera shake
  BipedLegs.gd      -- walk cycle (hip sweep, body bob)
  AIInputSource.gd  -- bot brain; Easy/Normal/Hard difficulty presets
  PlayerInputSource.gd
  WeaponBase.gd     -- ammo, fire rate, hit signal; FIXED and REFILLING magazine types
  MechDef.gd        -- Resource: mech stats, weapon slots, body scale
  BeaconMatch.gd    -- beacon scoring; drain model
  Match.gd / Player.gd / Pilot.gd / Ability.gd
  HUD.gd / Crosshair.gd / WeaponHUD.gd

resources/
  mechs/            -- MechDef .tres files (one per mech)
  abilities/        -- Ability .tres files (JumpHeal, Stealth)

shaders/
  health_bar.gdshader
  stealth_camo.gdshader

tools/
  penrose_gen.py    -- de Bruijn Penrose tile generator; outputs GDScript constants
  penrose_gen.gd    -- GDScript prototype (superseded by .py)

build/
  mechbattle_*.x86_64   -- versioned Linux binaries
```

Scenes live under `scenes/`: `arena/`, `beacon/`, `mech/`, `ui/`, `weapons/`.

---

## Architecture in One Paragraph

`InputSource → Player → Mech → Weapons`. The player is not the mech. `PlayerInputSource` and `AIInputSource` are interchangeable — bots use the same code path as the human player. `Mech` calls `fire()` on whatever weapon scenes are attached to its hardpoints; it does not know weapon types. New weapon = new `.tscn`, zero mech changes. `Game.gd` is the only autoload; match state lives in the arena scene and resets for free on scene change.
