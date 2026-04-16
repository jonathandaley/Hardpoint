# Mech Arena — Current Status and Next Steps

## Current state
1v1 player vs bot is playable. One weapon. Square placeholder mechs. Health bar has a color bug (not yet fixed).

## Immediate queue (in order)

1. **Fix health bar color bug**

2. **Title screen + hangar UI shell**
   - Title screen → sign-in flow → hangar
   - Hangar has tabs: Mech, Pilot. Mech might have a submenu to switch around weapons.
   - Matchmaking button leads into a match
   - Content stubs are fine — the shell just needs to exist so new mechs and weapons slot into something real

3. **Better mech visuals**
   - Player mech especially — third-person camera means you stare at it the whole match
   - Chunky-pixel 3D aesthetic: flat-shaded, limited palette, no textures-as-detail
   - Reference: Minecraft guardian/warden coarseness

4. **Mech classes: light, medium, heavy**
   - Differ in speed and health; heavies have shields
   - Slot into hangar mech tab
   - Architecture already supports this (tunable stats on Pawn)

5. **Additional weapons**
   - Target roster: shotgun, machine gun, rocket launcher, homing energy weapon, sniper
   - Light and heavy weapon classes; some types exclusive to certain slots
   - Slot into hangar loadout selection

6. **Leg turn inertia + leg animation**
   - Two distinct pieces:
     a. Turn speed / rotational inertia (movement code) — mech should not instantly reverse direction
     b. Leg animation following torso facing (visual only) — legs lag behind torso rotation, strafe animation when moving laterally
   - These can be separate sessions; inertia touches movement code, animation does not

7. **Arena One layout**
   - Desert setting, crashed ships, sandstone
   - Currently a flat test arena

## Notes
- Pilot abilities are passive bonuses; mech abilities are active (jump, dash, moveable shield)
- Stealth hides nametags/health bars, blends visually, but can still be shot
- Mid-match pickups with rarity tiers are planned but not in this queue
- Multiplayer remains deferred until single-player loop is solid
- **Account sign-in:** The "Enter Call Sign" screen is a placeholder. The game will require a real account — matchmaking, leaderboards, and pilot progression don't make sense as a guest. The sign-in screen needs to be replaced with proper account authentication before any online features land. This is deferred but must happen before multiplayer.
