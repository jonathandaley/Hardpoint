# Hardpoint Graphics Plan

## §G GOAL

War Robots-adjacent visual quality within Compatibility renderer constraints and T3500 hardware budget. Target: pixel-art-textured mechs, coherent arena environments, strong lighting atmosphere, good depth and distance. Fun and readable before polished.

## §C CONSTRAINTS

- Renderer: Compatibility (OpenGL ES 3.0). ⊥ SDFGI, SSAO, SSR, volumetric fog, GPUParticles3D.
- ⊥ normal maps (negligible benefit at target resolution, measurable fragment cost).
- ⊥ transparent materials (V7). All FX via opaque emissive + Tween.
- ⊥ real-time shadows from point/spot lights. Directional shadow evaluated per arena (G8).
- ⊥ per-frame runtime geometry generation; tools/*.py for offline bake (V13).
- Draw call budget: ~500 total for 6v6 match scene. Mechs target ~10 per mech.
- Texture atlas per mech: 128x128-256x256, nearest-neighbor sampled.

## §V INVARIANTS

GV1: ⊥ panel-line triplanar shader; produces wallpaper pattern unrelated to mech form
GV2: ⊥ per-face flat color as sole visual solution; insufficient surface interest
GV3: mech texture = pixel-art UV-mapped atlas, nearest-neighbor sampled; 4-5 color palette per mech
GV4: mech body = 30-60 primitives merged into one mesh + one atlas; legs separate for animation; one draw call per mech body
GV5: blob shadows via Godot Decal nodes; one decal per mech scaled by altitude; ⊥ real-time point/spot shadows
GV6: mountains = low-poly geometry ring outside arena bounds (⊥ skybox-painted); merged one draw call; fog-faded into atmosphere

## §T TASKS

id|status|task|cites
G0|.|collect hex palette (4-5 colors) + primitive layout brief for all 7 non-Slip mechs; blocks G11-G17|-
G1|.|Phase 0 audit: check render resolution, draw call baseline, frame time on T3500|-
G2|.|Slip geometry rebuild: 30-50 primitives in Blender|GV4
G3|.|Slip merge + UV unwrap: Blender Python script|GV4
G4|.|Slip texture atlas: 4-5 color palette, pixel-art zones; nearest-neighbor import|GV3
G5|.|Slip Godot integration and draw call verification (~10 calls target)|GV4
G6|.|Visual judgment gate: sign off Slip direction before proceeding to G11-G17|G5
G7|.|WorldEnvironment pass: tone mapping (Filmic/ACES), bloom, atmospheric fog|-
G8|.|Directional shadow test on T3500; enable for outdoor arenas if within budget|GV5
G9|.|Skybox upgrade: procedural sky or CC0 panoramic HDR|-
G10|.|Blob shadows: Decal node per mech, altitude-driven XZ scale|GV5
G11|.|Cesh geometry + texture|G0,G6
G12|.|Seeker geometry + texture|G0,G6
G13|.|Hornet geometry + texture|G0,G6
G14|.|Hippogriff geometry + texture|G0,G6
G15|.|Pegasus geometry + texture (jump thruster nozzles)|G0,G6
G16|.|Everest geometry + texture (front shield geometry)|G0,G6
G17|.|Vesuvius geometry + texture|G0,G6
G18|.|tools/mountain_gen.py: low-poly mountain ring generator|GV6,V13
G19|.|Mountain Godot integration: placement, scale, fog tint|GV6,G18
G20|.|Arena surface texture pass: Math Temple pixel-art stone/metal treatment|-
G21|.|Environmental decals: scorch marks, wear marks per arena|-
G22|.|Per-arena atmosphere tuning: fog color/density, point light review|-
G23|.|Weapons + effects pass: pixel-art atlas, muzzle flash/trails tuned for bloom|G7
G24|.|Mech geometry port: translate design/preview/brand-mech-render-*.html build() box lists into MechVisuals.gd per-mech funcs (negate Z, add rotation arg to _add_box, keep animated leg skeleton). Staged per weight class. Geometry only -- flat mats, no atlas|GV4
G25|.|Mech material upgrade: move mech mats off SHADING_MODE_UNSHADED to lit flat-shading + WorldEnvironment key/ambient/rim (this is most of why the design renders read well)|G7,GV2
G26|.|Mech palette recolor: pull per-mech armor/detail/emissive hex from design/preview/brand-mech-palette.html + legend swatches into MechVisuals.gd flat colors|G0
G27|.|UI polish pass: interpret design/ui_kits/game/*.jsx into HUD/menu changes; reconcile design/colors_and_type.css tokens against scattered inline Color() in HUD.gd|-

## Design system reference

design/ holds the Claude Design web kit (imported 2026-08-29, .gdignore'd). Relevant to graphics:
- brand-mech-render-*.html + mech-engine.js: box-model mech turnarounds in the SAME primitive language as MechVisuals.gd (boxes at x,y,z + armor/detail/emissive split + digitigrade legs). Coordinate diffs: kit faces +Z, Godot faces -Z; kit legs are free boxes, Godot legs are an animated node skeleton. Source for G24.
- assets/textures/*-armor.png / *-detail.png: 132x132 pixel-art tile pairs per mech -- candidate source art for the G4 / G11-G17 atlas track (still needs Blender UV unwrap G2/G3).
- colors_and_type.css: design tokens for G26/G27.
- HUD weapon icons already applied to assets/hardpoint/ (still need a Godot editor reimport pass; consider filter=nearest in the .import).
