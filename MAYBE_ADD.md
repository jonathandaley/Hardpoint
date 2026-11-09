# MAYBE_ADD.md -- ideas the user may want later (not queued)

Not tasks yet: nothing here is built until the user moves it to HUMAN_FOUND_ISSUES.md or says so.

- **Tracer rounds as a pilot skill** (user 2026-11-06, answering Q3: "Tracer rounds might end up as a toggleable pilot skill. Not sure yet; add the idea to a maybe-add list."). Earlier plan (T261, parked): rifles / snipers every round, MG every 3rd, a warm glowing streak grown from the muzzle; draft was in a session scratchpad, not in git.

- **Support mechs: Sapper, Medic, Davone, and their bot rule** (user 2026-11-08, after the risk rundown: "defer these three indefinitely, into MAYBE. Not sure I want to get into that. (And that means the new bot rule can wait, also.)"). Notes from the rundown: Medic is simple (heal burst + a terrain-hugging range ring like the beacon rings); Sapper is moderate (mines are replicated objects like pickups; careful: late joiners, trigger timing on lag, bot mine placement); Davone is careful (heal-over-time network volume, a heal gun outside the damage-only weapon path, Inverter Shield inside the core damage function); all three need support AI. The user's descriptions, as written:

  Bot new rule:
  Mechs without weapons aren't picked by bots when team size <4.



  Sapper: lays proximity mines, visually subtle. Medium speed, low health, no regular weapons. Mines do area damage. Ability recharge 7s. can have 5 mines active at a time. Placing a 6th deletes the oldest one with no explosion. Visually resembles a miner: brown, squat, wide domed mining hat with front light. Like a really bulky star wars pit droid.



  Medic: small, medium-fast, low health, one light. ability: heal all allies within the same radius as a beacon. Green circle denoting range, visible only to medic, painted on the ground if feasible (so that it adapts to uneven terrain). Grey with green cross emblem, green emissive accents.



  Davone: medium size, medium speed, low health, no weapons. Passive: heal all allies with a slow heal-over-time, rate dropping linearly with distance. Active: inverter shield: apply "Inverter Shield" effect to ally closest to crosshair, for 2 seconds. Inverter shield makes all damage recieved heal proportionally instead. 20s recharge.

  Has a built-in "weapon" equipped that shoots slow-moving green canisters that heal the first ally they hit.

  White with green accents. Has two antennae pointing backward at an angle. Health gun is a green emissive bump in center of chest.
