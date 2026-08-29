# Mech Arena — DESIGN.md

A mech FPS with modular weapons and area control, inspired by War Robots. Single-player loop first; multiplayer deferred until the game is fun against bots.

> **SUPERSEDED (2026-08-29): SPEC.md is canonical.** This file is the original design
> doc, kept as historical reference. Known-stale vs current state: internal res is
> 640×360 (not 320×180), art direction is Matrix-3 rust/neon (not white/grey/blue
> math temple), and multiplayer is largely built (T109-T128). Do not load this at
> session start; load SPEC.md.

---

## 1. Platform & tooling

- **Engine:** Godot 4
- **Renderer:** Compatibility (OpenGL ES 3.0). Not Forward+. Target is low-end hardware (T3500-class).
- **OS:** Debian (host: pomegranate)
- **Run mode:** Godot launched from terminal, not the editor play button, so stdout is directly readable.
- **Version control:** Frequent git commits. Roll back freely.
- **Budget:** Free assets only. No paid tools.

## 2. Visual style

- Chunky-pixel 3D: render at ~320×180 internal, blit nearest-neighbor to window.
- Flat shading, limited palette, no textures-as-detail.
- Reference point: Minecraft mobs (guardian, warden). Coarser than Lunacid or Dread Delusion.
- Arena tone: mathematical temple. White/grey/blue palette throughout.

### Locked non-goals
- No normal maps.
- No dynamic lighting tricks.
- No physics-based recoil or knockback. Mechs are too heavy to shove; damage numbers, screen kick, and muzzle flash sell impact. Revisiting recoil is a movement-system change, not a weapon flag.

## 3. Core architectural pattern: Player / Pawn split

The player is not the mech. The pipeline is:

```
InputSource  →  Player  →  Pawn (Mech)  →  Weapons (on hardpoints)
                    │
                    └──→  Pilot  →  modifiers on current Pawn
```

- **InputSource:** keyboard, AI, or network. Interchangeable.
- **Player:** owns hangar, lives, team, pilot. Possesses one pawn at a time.
- **Pawn (Mech):** owns hardpoints, base stats, accepts modifiers. Ignorant of who pilots it.
- **Weapon:** instanced scene attached to a hardpoint.

This split is non-negotiable from day one. Retrofitting it is painful; including it is nearly free. It makes bots (stage 3) and multiplayer (stage 5) into "new InputSource implementations" rather than rewrites.

## 4. Mech & weapon modularity

- `Mech` scene has named hardpoint child nodes: `HardpointLeft`, `HardpointRight`, etc.
- `Weapon` scenes are instanced as children of hardpoints at runtime.
- `Mech` calls `fire()` on whatever is attached. It does not know weapon types.
- New weapon = new `.tscn`. Zero mech code changes.

## 5. Match structure

- `Match` is a base class/scene. Mode subclasses inherit shared logic: teams, respawn, timer, win checks.
- `BeaconMatch`: owns beacon references, runs tick-down scoring. Stage 1/2 target.
- `DeathmatchMatch`: kill tracking, frag limit. Planned, not built yet.
- Arena scenes declare their match type.

## 6. Beacon mechanics (War Robots-style)

- Variable beacon count per arena. 5 is the reference; 3 for first playable.
- Each `Beacon` is an instanced scene with states: neutral / team A / team B / contested.
- Short capture timer. Not instant — instant capture degenerates with fast mechs.
- `Match` subscribes to beacon signals. Scoring tick subtracts from the team holding fewer beacons.

## 7. Hangar & lives

- `Player` owns a list of mech configurations and a life count. War Robots reference: 5 lives, swappable mechs.
- On death: pawn destroyed, life decrements, player picks next mech from remaining hangar.
- Stage 1 stubs this with 1 life. Architecture supports full hangar from day one.

## 8. Teams

- Two teams from day one. No free-for-all planned.
- Stage 1 "1 player vs 1 bot" is a 1-mech team vs a 1-mech team, not FFA.

## 9. Pilots & abilities

- `Pilot` is a small data object on `Player`: name, portrait, ability.
- Pilots apply **modifiers** to the currently possessed pawn (walk speed, reload rate, etc.). Modifiers attach on spawn, dissolve on pawn destruction.
- Mech stays ignorant of pilots — it just exposes tunable stats.
- **Abilities are first-class.** An `Ability` has a trigger (input or passive), cooldown, and effect. Both `Mech` and `Pilot` can contribute to the player's active ability set.
- Input pipeline routes as `InputSource → Player → {Pawn, Pilot}` so active abilities have a landing spot on either side.
- Conflict resolution between mech and pilot abilities is deferred until actually building them.

## 10. Game state

- `Game` autoload (singleton): profile, settings, cross-match state. **Only one autoload.** Resist adding more.
- `Match` node lives inside the arena scene: score, capture progress, alive mechs. Resets for free on scene change. Eventually the server-authoritative state owner.

## 11. Multiplayer authority (decided now, built last)

- **Server-authoritative with client prediction.** Godot's `MultiplayerAPI` and `MultiplayerSynchronizer`.
- Server simulates positions, damage, capture progress. Clients send inputs and predict their own mech locally.
- Bots are written as fake clients feeding inputs into the same pipeline. Stage 5 becomes "swap input source," not a rewrite.
- Bandwidth budget (six mechs, 20 Hz transforms + events) is well within T3500 / cheap wifi capacity.

## 12. Stage 1 defaults

- Third-person camera on a `SpringArm3D` child of the mech. Coolness factor, and the player mech needs to read well at chunky resolution.
- 1 player vs 1 bot.
- ~150×150m arena.
- 3 beacons.
- 3-second capture timer.
- Score to 1000.
- 1 life (hangar stubbed).
- Arena size and bot count exposed as `Match` config parameters.

## 13. Scope progression

1. Walking mech, one weapon, one map.
2. Beacon capture with timer.
3. Bot opponents.
4. Modular weapon system.
5. Multiplayer.

Multiplayer is the hardest part. Defer until the single-player loop is fun.

## 14. Working agreement

- Jonathan drives by feel: movement quality, visual correctness.
- Claude Code writes all code, manages git, reads terminal output, edits files, instruments with prints, maintains this document.
- Sonnet for day-to-day sessions. Opus for architecture decisions.
- Fresh Claude Code sessions per major subsystem to keep context lean.
- DESIGN.md is living documentation. Update it when decisions change; do not let it drift.
