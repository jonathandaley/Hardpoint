# Code-built mechs (T340)

Mechs designed in Code, in the design kit's box language. One builder per mech:
`tools/kit_mechs/<name>.js`. `tools/kit_port.py` turns every builder (and the kit's own
`design/preview/brand-mech-render-*.html`) into `scripts/MechKit.gd`; `MechVisuals` builds the
model from that at runtime.

## Workflow

```
python3 tools/new_mech.py Ironhide --class heavy     # first run: starting biped + stats
# edit tools/kit_mechs/ironhide.js to the description
python3 tools/new_mech.py Ironhide                   # rerun after every edit
# look at build/mech_review/Ironhide/lineup.png and armed.png, repeat
python3 tools/new_mech.py Ironhide --roster          # when it's approved: hangar + lobby
python3 tools/run_suite.py                           # kit_mechs, casing_clearance, mount probes
```

Each run ports every builder, writes the mech's pixel tiles from its palette line
(`tools/kit_tiles.gd`), imports them, gives it one weapon slot per mount, and renders a lineup
(next to Cesh, Pegasus and Everest, for scale and silhouette) and an armed close-up (front and
side). Stats in `resources/mechs/<Name>.tres` (health, speed, scales, description, abilities,
shields) are kept on reruns; a new mech starts from its class's reference (light Cesh, medium
Pegasus, heavy Everest) with no abilities or shields.

## The builder

```js
// palette: armor #RRGGBB, detail #RRGGBB, emissive #RRGGBB e2.0   (or: emissive none)
build: function (M) {
  const A = M.armor, D = M.detail, MO = M.mount, SK = M.socket, E = M.emis;
  ...
}
```

- `M.box(sx, sy, sz, px, py, pz, mat, rx, ry, rz)` -- a box: size, centre, material, rotation
  (radians; don't mix rx with ry / rz on one box).
- `M.between(a, b, thick, depth, mat)` -- a leg span from point a to point b.
- `M.glow(...)` -- ignored in the game (a kit preview light); harmless to keep.
- Materials: `A` armor and `D` detail (pixel tiles in the palette colours), `MO` mount and
  `SK` socket (neutral dark), `E` glow (the palette's emissive colour, speckled like the armor).

**Space:** kit space, metres at body_scale 1: +Z is the mech's front, +Y up, ground at y = 0,
x = 0 the centre line. Class sets `body_scale` (light 0.85, medium 1.0, heavy 1.25).

**Order (kit_port reads legs by position in the call list):**
1. torso, head, shoulders, mounts, anything above the hips;
2. the pelvis: a box at x = 0 (not `E`);
3. per side (`[-1, 1].forEach`): the hip box, exactly three `M.between` spans (thigh, shin,
   pastern) starting at the hip box's centre, then the toe pad box. Extra leg details after the
   toe pad attach to the nearest joint. The game animates its own 3-segment legs from these
   thicknesses / depths, the hip spacing, the toe pad and the pelvis.

**Mounts become weapon slots:** `MO` boxes within 0.4 m of each other are one hardpoint; one box
is a light slot, two or more a heavy slot. Put the mount on the front face of a shoulder or
body block -- casings leave mid-gun (T337) and must not fly through the body
(`casing_clearance` probe once it's in the roster).

**Scale references (body_scale 1):** heads at y ~2.0, pelvis ~0.95, shoulder mounts y 1.5-1.6
at x ~0.65. Lights stand ~2 m, heavies ~2.6 m tall after scaling.

## Examples

`lynx.js` (light, digitigrade cat), `warhog.js` (heavy, boar tank) -- stubs not in the roster;
the kit's nine (`design/preview/brand-mech-render-*.html`) use the same API.
