# This file is for humans to list bugs or other issues where Claude can see them. Not all of these are fixable without discussion, but some of them should be able to be fixed autonomously. Fixed bugs should be deleted, the record can live in SPEC. 

Top priority for this list: crosshair is too hard to see through. Make it only the current width at the edges, and narrow it to a point in the middle for greater visibility.

Mech balancing automatically: wide variety of team sizes and maps, weapons. Write the data to a file, including both total winrate/damage but also "kestrel weak against everest" etc.

Patterned emissives, on the mech textures, also probably a toggle, as the glow probably costs something. (T255 attempt reverted 2026-11-05 -- "totally broken"; waiting on new instructions here)
Add slight variatons in the glowing/emissive parts of the mechs that are already glowing. No adding anything new. Make a note to never put anything "at panel seams" again, because you've done things like that several times now and it is never even close.

Machine gun barrel should start glowing as ramp-up increases, red-hot at max speed.

Gun shells should stick around longer, at least at higher graphics settings. I don't actually see the spent shells at all anymore, where did they go?

Add drops: coins for bots, powerups, 

Bot drops are based on their difficulty

General weapon mount size/weapon size checkup

Bots should eject on death like players

Team size should not be in hangar- I think that's entirely stale as it's part of setting up a match now.

Rangefinder should activate at the same time as the targeting reticle

Always-on rangefinder should be available as a pilot skill, only one level. Once bought, togglable. R?

Check for rocket launcher accuracy? Didn't work in Sydney, not sure what was up with that. 

Map picker in singleplayer should have a play button so that picking a map doesn't immediately start it.

Badlands should have some decrepit windows in the buildings.

Self destruct option in esc menu, just kill the current mech.

Don't spawn the first mech until it's picked (currently spawns the first mech then switches)

Beacon capture count at end of match is wrong (only tried singleplayer): everyone on each team gets counted for every beacon.

Bots should pick spawnpoints instead of all spawning together.

Guns should list their range in the description

Bogged down status effect should have a HUD icon and slowdown % listed

Death match (no beacon) match option

Make sure elite bots don't miss, and in fact shoot ahead of moving targets. I want elites to be impossible. Can always add more intermediate levels if necessary.

Remove the two big stationary drones in the hangar.

Arc weapon should be unable to fire until it's within range.

Kestrel shield is too strong.

Missile explosion visual is 20% too big.

Cesh bots should use stealth more intelligently.

Missiles should explode once they hit maximum range, regardless of whether they hit anything.

Arc weapon visual is sometimes broken, seems to always work for bots? Flaky error.

Beacon contested in stealth stays contested indefinitely.

Rangefinder toggle is actually not what I wanted. Remove everything about the pilot skill; instead, make the only rangefinder be always-active, and only show distance to an enemy that's in the targeting reticle. So no range shown looking at a wall, unless there's an enemy behind it.

Patience damage should scale higher; human testing shows sniper to be vastly better than patience in every situation I tried.

Laser and arc should not go through targets, but stop when hitting a mech.

Factory should have less atmosphric haze.

Pegasus sometimes heals too much in a single jump?

Factory yellow bands around some of the buildings are at the same depth, so flicker.

Corvette feels very spread out, shrink it by 30%.



Harden security for network: Look through the source code for vulnerabilities, and also try to hack it from the outside if possible. Defer for now, but flag it before setting up online stuff.

Make a tutorial - defer, just have the note somewhere. Also a manual in settings.

