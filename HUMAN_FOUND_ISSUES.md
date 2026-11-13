# This file is for humans to list bugs or other issues where Claude can see them. Not all of these are fixable without discussion, but some of them should be able to be fixed autonomously. Fixed bugs should be deleted, the record can live in SPEC. Don't ask questions in this file; move the task, with your question, to NEEDS_HUMAN.md.

Texture leak also occurs in exiting after playing on Corvette, although I did play on Factory earlier in the session. Most of the maps, actually, but Corvette last.

Bots in hangar point their weapons 30 degrees down, should be level.

Health bars and name tags should be above the targeting reticle, instead of crunched into it.

Powerups should have a hud indicator like "bogged down" for the ongoing effect ones.

Energy shield health should be visible to others, blue bar under the health bar.

A bot (kestrel) fell off the back of Redwood Forest. Debug, and also add something that kills bots that fall off, just in case, to prevent broken matches. Looks like the dip in the back can be walked off by any bot.

The skill tree is cramped and messy. Make it only have right angles in the connecting lines, no angled lines. Lines should only go to direct children/parents, not anywhere else.
Skills that are available but have insufficient coins to purchase should not be greyed out, but have the cost to upgrade in red. Skills that are available to buy should have the SP cost listed, and be red if no SP.

Taurus lunge physics tweaks:
Short crouch anticipation, explosive front-loaded acceleration (ease-out), committed momentum with no steering, hard braking plant with a slight overshoot and settle, and bypass normal ground accel/decel during the lunge.
The "overshoot" should be cancelled if it hits a wall or mech, so that it just settles out of the impact.
Crouch should last .1 seconds. Recharge time should decrease with each consecutive hit? 

Elites should have different hangars based on game mode.

Machine gun barrel doesn't cool down when stop firing, on bots. Works fine on my gun. Figured something out: Glow happens when mouse is pressed, not when gun is actually firing.

Under some circumstances, not sure exactly when, TAB will start spectating from a mech. Might be after switching back to the game window while the game was left running unpaused? It's happened a couple of times but I'm not exactly sure.

Slip legs are weird, should probably have a more loping stride. If that's not hard, make its stride frequency like Cesh's, but with a longer step so its speed remains the same.

Aerial strike is a little too big on Seeker. (visually)

Match end results screen is spaced funny; the numbers should not be dependent on the name length, but be in columns.

Make the edges of the maps disappear into fog, so the hard world border isn't as jarring. The physical edges are good where they are now, just visual needs an upgrade.

Improve mech descriptions: they currently barely mention shields, and don't mention abilities at all. Also add some lore; you make it up based on the mechs abilties and colors and I'll tweak if necessary.

How hard would it be for bots to sometimes see through stealth? If not, something like "Bot difficulty * how "noisy" you're being = likelihood to be noticed".

Targeting reticle should be grey if no equipped weapon is within range. There should be no max distance at which it appears.

Change mech preview in hangar to a drag-and-spin if that's easy. Arrow buttons to rotate it 45 degrees would also be fine and probably easier. Stationary 3/4 default view.

"Select spawn point"  should be more visible, a different color, bigger across the top when picking mechs in a match.

Deathmatch should count kills instead of mechs remaining, in case team sizes are different.

Arc weapon should increase damage as range decreases. Current damage is good for reasonably long range.

Coins should not vanish.

Powerups should appear 50% more often.

On Badlands, a damage powerup spawned in the sky and floated there. No obvious reason.

Spent shells float in the air sometimes.

Swamp needs better pathfinding: there are some impassible choke points that all the bots, including elites, were stuck on. Probably the --I don't remember what it's called, navigation map thing-- needs to be updated for Swamp.

Normal-level bot shoots missile launcher when out of range.

## Deferred:

The general texturing applied to most of the maps' floors and obstacles is pretty good in general, but it looks blurry. Probably make the pixels/texels bigger? Like the bot texture, sharp bigger pixels instead of blurry finer detail. Not for every map, though: Redwood's floor is great.

Harden security for network: Look through the source code for vulnerabilities, and also try to hack it from the outside if possible. Defer for now, but flag it before setting up online stuff. Network check goes before network setup.

Make a tutorial. Also a manual in settings.

