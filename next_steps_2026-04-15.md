# Mech Arena — Current Status and Next Steps

## Current state (as of Apr 15, session 2)

1v1 player vs bot is playable. Title screen → sign-in → hangar → arena flow exists.
One weapon (raycast rifle). Placeholder box mechs. Viewport at 640×360.
Match-over returns to hangar. Health bars working (player top-left, bot screen-space).

---

## Build queue

Steps are ordered by downstream impact. Items marked **[BLOCKS →]** must be done before
what they list. Do not start an item until its blockers are complete.

---

### 1. Mech node hierarchy (legs / torso split)

**BLOCKS → visuals, animation, inertia**

Currently the entire mech (body mesh, hardpoints, camera arm) is parented flat to the
CharacterBody3D root and rotates as one unit with mouse look. The mechanic of
aim ≠ movement direction already exists (you can strafe), but it has no visual expression —
the whole body always faces aim direction.

Target hierarchy:
```
Mech (CharacterBody3D)
  Legs (Node3D)               ← will rotate toward velocity direction
    LegMesh (MeshInstance3D)
  Torso (Node3D)              ← rotates with mouse look (current behavior, just isolated)
    BodyMesh (MeshInstance3D)
    HardpointLeft (Node3D)
    HardpointRight (Node3D)
    CameraArm (SpringArm3D)
      Camera3D
  CollisionShape3D
```

Also fix in this pass: RaycastGun currently finds its owner via `get_parent().get_parent()`.
Give weapons a direct owner reference set at setup time — this breaks with any tree change.

---

### 2. MechDef resource + dynamic arena spawning

**BLOCKS → named mech roster, hangar selection working end-to-end**

Stats currently live as `@export var` on Mech.gd. Two mech instances are baked into
Arena.tscn. Hangar selection can never work from this.

Define a `MechDef` Godot Resource:
- display_name (e.g. "Griffin")
- class_tag ("Light" / "Medium" / "Heavy") — descriptor only, not primary key
- max_health, walk_speed, has_shields
- hardpoint_count / hardpoint_config
- scene: PackedScene (the mech scene variant to instantiate)

Store the player's chosen MechDef in Game state. Arena reads it and spawns dynamically
instead of using baked nodes.

Settle Game.gd profile shape here: fields the server will eventually own
(wins, losses, loadout) vs. fields that stay local (mouse sensitivity).
Don't conflate them — migration will be easier.

---

### 3. Named mech roster

**Requires: 1, 2**

Every player gets the same catalog of named mechs — no unlocks at this stage.
Each named mech is a MechDef .tres file (e.g. Griffin.tres, [TBD].tres).
Light/medium/heavy is a tag on the card, not the organizing concept.
Hangar mech tab shows the roster; player picks one before hitting Find Match.
Weapon slot restrictions (if any) key off hardpoint config, not class tag.

Start with Griffin (medium, current stats). Add 1–2 more named mechs as stubs
so the roster UI has something to show.

---

### 4. Weapon system: clean base + additional weapons

**Requires: 1** (owner ref fix from step 1 is prerequisite)
**BLOCKS → additional weapons**

WeaponBase is solid. Before adding more weapons, settle one thing:
hitscan (RaycastGun) vs. projectile (rockets, homing) are fundamentally different —
projectile weapons need physics objects in the scene. The base class should make
the pattern explicit so subclasses don't mix them up.

Then add weapons from the target roster:
- Shotgun (hitscan, spread)
- Machine gun (hitscan, high fire rate, low damage)
- Rocket launcher (projectile, splash)
- Homing energy weapon (projectile, tracking)
- Sniper (hitscan, long range, slow fire rate)

Weapon type exclusivity per hardpoint slot slots into MechDef hardpoint config.

---

### 5. Better mech visuals

**Requires: 1** (hierarchy must be settled before mesh work)

Chunky-pixel 3D aesthetic: flat-shaded, limited palette, no textures-as-detail.
Reference: Minecraft guardian/warden coarseness.
Player mech especially — third-person camera means you stare at it the whole match.
With Legs and Torso as separate nodes, mesh swaps are localized and clean.

---

### 6. Leg inertia + leg animation

**Requires: 1** (legs/torso split is the prerequisite for both)

Two distinct pieces — can be separate sessions:

a. **Inertia** (movement code): Legs rotate toward velocity direction with lag.
   Torso continues to track aim. Creates the War Robots-style waddle feel.
   Mech can no longer instantly reverse direction.

b. **Animation** (visual only): Leg mesh animates to match movement — strafe,
   forward, backward, idle. Does not touch movement code.

---

### 7. Arena One layout

**Requires: nothing** — independent, can slot in at any point

Desert setting, crashed ships, sandstone. Currently a flat grey test arena.
Natural to do after visuals (step 5) so the aesthetic reads together, but not required.

---

## Deferred / design-adjacent

**Account sign-in:** The "Enter Call Sign" screen is a placeholder. The game requires a
real account — matchmaking, leaderboards, and pilot progression don't make sense as a
guest. Replace with proper account auth before any online features land.
Design the profile data split (step 2) with this in mind.

**Multiplayer:** Deferred until the single-player loop is solid.

**Pilot abilities:** Passive bonuses. Not in this queue.

**Mech abilities:** Active (jump, dash, moveable shield). Not in this queue.

**Mid-match pickups:** Rarity tiers planned. Not in this queue.

**Stealth:** Hides nametags/health bars, blends visually, still shootable. Not in this queue.
