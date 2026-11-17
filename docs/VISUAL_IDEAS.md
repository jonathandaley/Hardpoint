# Visual ideas (2026-11-17 survey)

Made from a render survey of every map (`tools/art/map_survey.tscn`: 8 fixed viewpoints a map) and a
geometry check for floating / hovering pieces. Contact sheets: `docs/review/visual_survey/`.

Your direction (2026-11-17): chunky pixels over blur (mechs are the reference), more detail,
Sydney's skyscrapers are great but its small buildings are boring, redwood trunks poke out above the
leaves, floating pieces in Factory and Giza.

**Queued** = I build it (render before/after in `docs/review/T<n>/`, a probe where it can be
measured, draw calls checked, an off-switch for anything that costs frame time).
**Your call** = changes a map's character; I won't build these until you say so.

## Queued

| Task | What |
|---|---|
| T438 | Redwood trunks end inside the canopy. Today a trunk runs its full height `h` while the crown is centred at 0.85 h with half-height 1.5 r, so 3-11 m of bare trunk sticks out above every crown. A probe checks the crown top is above the trunk top. |
| T439 | Floating and hovering pieces, every map. Giza: temple roofs sit at a fixed height while their pillars follow the dunes, so roofs hover 0.4-1.1 m over 10 pillars. Badlands: 3 pieces fully in the air, 14 posts short of what they hold up. On slopes (Forest 59, Badlands 35, Swamp 10, Giza 4, Math Temple 3), props sit at the ground height of their centre, so the downhill edge hangs in the air. Fix: sink props to the lowest ground under them. Probe `floating_parts` keeps it that way. **Factory: the check finds nothing static floating, so I need a pointer from you (see NEEDS_HUMAN).** |
| T440 | Chunky-pixel textures (unparks T305). Map obstacles get a soft 128 px noise with smooth filtering (`MapScene.add_surface_detail`); floors on several maps blur the same way. Switch to low-res pixel textures with nearest filtering, at about the mechs' texel size. Redwood's floor stays as it is (you liked it). |
| T441 | Sydney small buildings. Today they're grey boxes with a window grid. Add: sandstone / brick / rendered-concrete facade colours, a lit shopfront band with an awning strip at street level, a parapet lip, roof clutter (AC units, water tank, stair hut), and varied heights within a block. Everything merges per material, so draw calls stay about the same. |
| T442 | Redwood canopy, ferns and trunk flares. From below, crowns read as flat green lily pads (squashed spheres); make them clumps of 3-4 overlapping blobs with darker undersides and pixel leaves. Ferns are single bright-green wedges that look like confetti; make 4-5-blade clumps in a mossier green. Fix the visible seam ring where the root flare meets the trunk. |
| T443 | Giza stone. Pyramids are smooth, so add block courses as a pixel texture: horizontal lines, a step every ~1.5 m. Make the causeway slabs and casing stones read as cut stone. |
| ~~T444~~ | Dropped: the coloured boxes I took for cars are kiosks; they got their own dressing in T441. |

## Your call -> approved 2026-11-17, queued T445-T451

User: "All your ideas sound good, except keep the moody fog in Swamp." So Swamp keeps its fog as is; the rest of its dressing goes in.

- **Giza sky.** It's one flat tan; a sun disc and a gradient (paler near the horizon) would add depth. Lighter fog would show the pyramids from further away.
- **Swamp mood.** The fog is heavy enough that the whole map is one olive tone. ~~a slightly lighter fog with a cooler tint near the water~~ (no: the fog stays); reeds and lily pads at the water's edge; hanging moss on the dead trees; fireflies (with an off-switch).
- **Factory dressing.** Pipe runs along the bulkheads, hazard stripes on the ramp edges, a gantry crane over the deck, painted deck numbers by the beacons. The deck itself works; the bulkheads are plain slabs.
- **Badlands ruins.** The walls are flat adobe colour. An adobe-brick pixel texture plus a few rusted vehicle hulks or dead shrubs between the ruins.
- **Sydney streets.** Lane markings, crosswalks and kerbs (all flat, cheap).
- **Beacons.** The poles are thin grey lines; a plinth at the base and a team-coloured light at the top would read better from a distance. Gameplay-adjacent, so it's your call.
- **Corvette.** Not surveyed: it's indoor and the survey camera sat outside. Next pass.
