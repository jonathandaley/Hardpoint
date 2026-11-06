# This file is for humans to list bugs or other issues where Claude can see them. Not all of these are fixable without discussion, but some of them should be able to be fixed autonomously. Fixed bugs should be deleted, the record can live in SPEC. You may rearrange these tasks and group them in ways that make sense; they're in the order I found or thought of them, unless otherwise specified, with no inherent priority.

Mech balancing automatically: wide variety of team sizes and maps, weapons. Write the data to a file, including both total winrate/damage but also "kestrel weak against everest" etc.

Gun shells should stick around longer, at least at higher graphics settings. I don't actually see the spent shells at all anymore, where did they go?

Bots should eject on death like players

Check for rocket launcher accuracy? Didn't work in Sydney, not sure what was up with that. 

Badlands should have some decrepit windows in the buildings.

Self destruct option in esc menu, just kill the current mech.

Don't spawn the first mech until it's picked (currently spawns the first mech then switches)

Bots should pick spawnpoints instead of all spawning together.

Death match (no beacon) match option

Make sure elite bots don't miss, and in fact shoot ahead of moving targets. I want elites to be impossible. Can always add more intermediate levels if necessary.

All lock-on weapons should not lock on until the weapon is within range. Square reticle should still be visible at any range. 

Kestrel shield is too strong.

Cesh bots should use stealth more intelligently.

Arc weapon visual is sometimes broken, seems to always work for bots? Flaky error.

Laser and arc should not go through targets, but stop when hitting a mech.

Corvette feels very spread out, shrink it by 30%.

Sign up screen isn't scrollable, so currently makes it so you have to exit the game to leave the screen. Both login and signup have a "server" field, what is that for? That's not a normal thing with other games, so if that's necessary for some reason it should probably be moved somewhere else.

ERROR: Texture with GL ID of 63: leaked 349524 bytes.
   at: ~Utilities (drivers/gles3/storage/utilities.cpp:77)
This error appeared after closing the game.

Targeting reticule should aim for center mass, instead of the current spot (appears constant, so it's a little low on a pegasus and very low on a vesuvius).

Redwood trees texture should be coarsened and made higher contrast. If feasible, lengthening the texture vertically somewhat would be great. I'm not exactly sure how to describe it; the goal is a tree bark-like texture, so aligning the dark and light parts vertically for a few pixels at a time, not necessarily straight up-and-down but just generally. Is that relatively easy?

The mech picker for matches should look like a miniature version of the hangar, without any of the fancy parts; no light cones, drones, etc. Just enough to see what weapons they have equipped so you can tell the difference between mechs with the same name in the squad.

Top left of HUD, under the ability marker, should have a readout, small text, listing kills and chat. Chat as a stub; kills very simple. Should take up very little space and not be distracting.

Bots should be assigned names, which are visible like players (Which I can't remember if they're already visible, but in multiplayer the callsign should be above the health bar). You make a list of names that sound cool and have nothing objectionable in them (this is a shooter game, MurderousMaximus27 etc. is totally fine, but not DeeezGunz69). That way names are assigned from a preset list, but aren't just random. Make the list long enough so that repeats aren't constant. (100-200?)

At elite level, bots will have a much shorter, separate list of names. Only good gamertags; cheesy ones are fine for the basic bots, but not elites. These will have persistent pilot upgrades that are tied to their names, so, e.g. Inexorable always has "health" and the whole "move speed" tree maxed out.

Pilot upgrades will be the difference between hard and elite. Hard will have no intentional bad strategy/aiming errors, elite will be that plus upgrades.

How hard would it be to make the weapons tilt up and down as they aim? If easy, add it to the queue.

Game lagged when shot at close range with three heavy shotguns at once. Too many particles? Want to make sure that doesn't happen.


Make rockets be smarter to avoid hitting obstacles.



Defer until I decide more: The general texturing applied to most of the maps' floors and obstacles is pretty good in general, but it looks blurry. Probably make the pixels/texels bigger? Like the bot texture, sharp bigger pixels instead of blurry finer detail. Not for every map, though: Redwood's floor is great.



Harden security for network: Look through the source code for vulnerabilities, and also try to hack it from the outside if possible. Defer for now, but flag it before setting up online stuff.

Make a tutorial - defer, just have the note somewhere. Also a manual in settings.


### Question from Claude (2026-11-05 late)

Q3: "Tracer rounds?" dropped out of this list in your cleanup. Still want tracers (rifles/snipers every round, MG every 3rd, a warm glowing streak)? Holding it (T261) until you say. The machine-gun bug I found on the way (clients never see MG bullets) gets fixed either way.
Tracer rounds might end up as a toggleable pilot skill. Not sure yet; add the idea to a maybe-add list.

Q4 (T266, from Claude 2026-11-06): true online (lemon.limedaley.com) is next in the queue. You asked me to flag the network security review (T290) before any online work -- flagging it now. Do T290 first, or go ahead with T266? Skipping T266 until you say.

Q5 (T263, from Claude 2026-11-06): there has never been spent-shell code in the game (I searched all of git history). What you saw was probably the grey smoke puffs each bullet leaves along its path (they shrink away in 0.18 s) or the orange impact sparks (gone in ~0.2 s). Which did you mean -- or do you want real casings ejected from the guns (falling, bouncing, lingering longer at higher effect settings)? Holding T263 until you say.

Q6 (T301, from Claude 2026-11-06): Pegasus's jump heals exactly once per jump (checked: mashing the key through a jump gives one heal; the 16 s cooldown blocks the rest) -- but it is a flat +80 HP, 27% of Pegasus's 300 at once, which may be what reads as "too much". Lower it (e.g. +50), make it a % of max HP, or heal over the jump instead of instantly? Leaving it at +80 until you say.
