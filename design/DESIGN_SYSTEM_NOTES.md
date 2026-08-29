# Hardpoint — working notes

## ⚠️ Digitigrade / reverse-knee legs — I keep getting this wrong. Read before touching any leg.

Mech legs in this project are **digitigrade (reverse-knee), like a bird/raptor hind leg** — NOT a human knee. I have repeatedly flattened them back into a normal forward-bent knee. Don't.

The silhouette that MUST be visible:
- A joint that **kicks backward** (the hock). This backward joint is the whole point — if it isn't clearly behind the hip, the leg is wrong.
- The **heel stays raised** — the mech walks on its toes. Do NOT put a flat foot plate on the ground under the whole leg.

Correct joint chain, top → ground (z = forward, y = up):
1. **hip** — top.
2. **knee** — down and slightly **forward** of the hip.
3. **hock** — down and strongly **backward** (behind the hip). ← this is the "reverse knee".
4. **toe** — down and **forward** again, on the ground; heel/hock raised above it.

So the path zig-zags: forward → back → forward. Three bones: thigh (hip→knee), shin (knee→hock), pastern/metatarsus (hock→toe). Build bones with a between-two-points helper, not by eyeballing a single rotation — guessing one rotation angle is how I get it backwards.

Quick self-check before declaring done: in the SIDE view, is there an obvious joint sticking out *behind* the vertical line of the hip, with the foot/toe forward and the heel up? If not, it's a normal knee — fix it.

Source of truth for proportions: `preview/brand-mech-blockout-slip.html` (3 leg segments + hip + foot, "digitigrade reverse-knee").
