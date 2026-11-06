# This file is for humans to list bugs or other issues where Claude can see them. Not all of these are fixable without discussion, but some of them should be able to be fixed autonomously. Fixed bugs should be deleted, the record can live in SPEC. You may rearrange these tasks and group them in ways that make sense; they're in the order I found or thought of them, unless otherwise specified, with no inherent priority.

Gun shells should stick around longer, at least at higher graphics settings. I don't actually see the spent shells at all anymore, where did they go?

Defer until I decide more: The general texturing applied to most of the maps' floors and obstacles is pretty good in general, but it looks blurry. Probably make the pixels/texels bigger? Like the bot texture, sharp bigger pixels instead of blurry finer detail. Not for every map, though: Redwood's floor is great.

Harden security for network: Look through the source code for vulnerabilities, and also try to hack it from the outside if possible. Defer for now, but flag it before setting up online stuff.

Make a tutorial - defer, just have the note somewhere. Also a manual in settings.

### Question from Claude (2026-11-05 late)

Q4 (T266, from Claude 2026-11-06): true online (lemon.limedaley.com) is next in the queue. You asked me to flag the network security review (T290) before any online work -- flagging it now. Do T290 first, or go ahead with T266? Skipping T266 until you say.

Q5 (T263, from Claude 2026-11-06): there has never been spent-shell code in the game (I searched all of git history). What you saw was probably the grey smoke puffs each bullet leaves along its path (they shrink away in 0.18 s) or the orange impact sparks (gone in ~0.2 s). Which did you mean -- or do you want real casings ejected from the guns (falling, bouncing, lingering longer at higher effect settings)? Holding T263 until you say.

Q6 (T301, from Claude 2026-11-06): Pegasus's jump heals exactly once per jump (checked: mashing the key through a jump gives one heal; the 16 s cooldown blocks the rest) -- but it is a flat +80 HP, 27% of Pegasus's 300 at once, which may be what reads as "too much". Lower it (e.g. +50), make it a % of max HP, or heal over the jump instead of instantly? Leaving it at +80 until you say.
