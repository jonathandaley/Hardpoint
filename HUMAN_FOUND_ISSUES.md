# This file is for humans to list bugs or other issues where Claude can see them. Not all of these are fixable without discussion, but some of them should be able to be fixed autonomously. Fixed bugs should be deleted, the record can live in SPEC. Don't ask questions in this file; move the task, with your question, to NEEDS_HUMAN.md.

Q6 (T301, from Claude 2026-11-06): Pegasus's jump heals exactly once per jump (checked: mashing the key through a jump gives one heal; the 16 s cooldown blocks the rest) -- but it is a flat +80 HP, 27% of Pegasus's 300 at once, which may be what reads as "too much". Lower it (e.g. +50), make it a % of max HP, or heal over the jump instead of instantly? Leaving it at +80 until you say.
I'm pretty sure it glitched and healed full from 20%. I may have missed something, but I think that's what happened. Only happened once.

Mech picker in battle should allow clicking on the mech picture, in addition to its name.

Multiple bots of same type in hangar can't have different weapons anymore? Pretty sure that used to work correctly, but now changing one changes all.

ERROR: Texture with GL ID of 36: leaked 349524 bytes.
   at: ~Utilities (drivers/gles3/storage/utilities.cpp:77)
ERROR: Texture with GL ID of 78: leaked 349524 bytes.
   at: ~Utilities (drivers/gles3/storage/utilities.cpp:77)
ERROR: Texture with GL ID of 37: leaked 349524 bytes.
   at: ~Utilities (drivers/gles3/storage/utilities.cpp:77)
ERROR: Texture with GL ID of 82: leaked 349524 bytes.
   at: ~Utilities (drivers/gles3/storage/utilities.cpp:77)
On exit from game (only played on factory if that matters)

Skill tree visual upgrade: actual branching tree, or really, root system, with the lowest tiers at the top. Like Age of Empires II tech tree. 

Patience damage should scale exponentially with charge level. Same max.

Patience yellow charge bar in hud should switch to purple on reaching full.

Cheaper to have each bot have a preset hangar, so a weighted random isn't necessary? 

Elites definitely should have preset hangars.

Elites should have a modified AI with personality.

Elites should have a hangar that makes sense with their abilities and playstyles.

Some kind of indicator when picking up drops, including their effect.

Bots should go for powerups, but can't pick up coins.

Visually, bots appear to aim high? Also players. Make sure level camera means level gun. Actual bullets fire correctly, it's just the visual that's off.

Any bots with cesh should use stealth intelligently. Remove it from the roster at lower difficulties.

New mechs: 

Taurus: medium size, very low speed*, medium health, two lights.

Ability: Charge: no recharge time. While spacebar is pressed, lock movement straight forward and disable mech rotation. Accelerate forward linearly, starting at normal (slow) speed and scaling. Releasing spacebar decelerates quickly, not instant. Release instantly unlocks steering and directional movement, so turning quickly and pressing spacebar again can preserve a small amount of the boost.

While spacebar is pressed, deal moderate damage to colliding mechs based on relative speed. Floor for damage should be pretty high; no minor damage from repeated small hits. Red and maroon with some black. Crimson emissives. Shaped like a hunched minotaur, horns in front. Light weapons instead of arms. While charging, emit red glow that intensifies with speed.

## Deferred:

The general texturing applied to most of the maps' floors and obstacles is pretty good in general, but it looks blurry. Probably make the pixels/texels bigger? Like the bot texture, sharp bigger pixels instead of blurry finer detail. Not for every map, though: Redwood's floor is great.

Harden security for network: Look through the source code for vulnerabilities, and also try to hack it from the outside if possible. Defer for now, but flag it before setting up online stuff. Network check goes before network setup.

Make a tutorial. Also a manual in settings.

