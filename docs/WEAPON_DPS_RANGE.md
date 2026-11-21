# Weapon sustained DPS vs range (T539)

Measured in the engine (`python3 tools/weapon_dps_range.py`): an Elite bot holds the trigger 60 s at a mech-sized target (no shields, no skills / powerups) at each distance; reloads, spread, falloff, travel time, splash and lock time all count. Each cell: **still** / strafing target (walks left / right across the line of fire, turning every 1.5 s); the median of 3 runs. Blank = past 95% of the weapon's range (bots don't fire there); "-" = no run.

## Light

| weapon | 10 m | 30 m | 60 m | 110 m | 180 m |
|---|--:|--:|--:|--:|--:|
| RIFLE LT | **5.5** / 3.8 | **5.8** / 3.1 | **3.2** / 0.7 |  |  |
| SNIPER LT | **11.3** / 11.3 | **12.0** / 12.0 | **11.3** / 8.7 | **9.2** / 6.0 | **12.0** / 2.7 |
| MG LT | **9.6** / 7.7 | **5.0** / 4.3 | **1.4** / 0.7 |  |  |
| SHOTGUN LT | **8.1** / 12.2 | **0.7** / 0.7 |  |  |  |
| MISSILE LT | **10.0** / 7.3 |  |  |  |  |
| ROCKET LT | **3.0** / 3.0 | **0.1** / 3.0 | **3.0** / 0.0 | **3.0** / 2.0 |  |
| LASER LT | **2.7** / 2.7 | **2.9** / 2.9 | **2.7** / 2.7 | **2.9** / 2.9 |  |
| ARC LT | **10.0** / 10.0 | **7.3** / 7.7 | **4.0** / 4.0 |  |  |
| INFERNO LT | **12.8** / 12.8 |  |  |  |  |

## Heavy

| weapon | 10 m | 30 m | 60 m | 110 m | 180 m |
|---|--:|--:|--:|--:|--:|
| RIFLE HV | **4.8** / 3.0 | **5.7** / 1.5 | **3.8** / 1.0 |  |  |
| SNIPER HV | **12.0** / 13.0 | **13.0** / 12.0 | **13.0** / 5.0 | **13.0** / 5.0 | **14.0** / 3.0 |
| MG HV | **18.9** / 18.6 | **12.7** / 8.2 | **2.9** / 0.9 |  |  |
| SHOTGUN HV | **21.6** / 31.3 | **2.1** / 2.6 |  |  |  |
| MISSILE HV | **13.5** / 10.3 |  |  |  |  |
| LASER HV | **5.1** / 5.1 | **5.5** / 5.5 | **5.1** / 5.1 | **5.6** / 5.1 |  |
| ARC HV | **14.6** / 14.6 | **11.3** / 11.3 | **5.8** / 5.8 |  |  |
| MORTAR HV | **18.0** / 5.1 | **17.4** / 11.1 | **15.4** / 15.1 | **15.1** / 14.1 |  |
| INFERNO HV | **29.2** / 29.2 |  |  |  |  |
| ORBITAL HV | **15.5** / 12.8 | **15.5** / 12.4 | **13.2** / 14.0 | **17.5** / 10.5 | **17.5** / 14.5 |
| SWARM HV | **3.7** / 3.9 | **3.8** / 3.6 | **3.8** / 0.8 | **0.9** / 3.6 | **3.0** / 3.1 |
| PATIENCE HV | **8.7** / 8.7 | **8.7** / 8.7 | **4.5** / 4.5 | **8.7** / 0.0 | **8.7** / 0.0 |


## Reading it (2026-11-20, first run)

- One 60 s bot duel swings a lot even as a median of three (MG LT 30 m: 4.3 / 8.6 in one pass, 5.0 / 4.3 in the next): read differences under ~30% as noise.
- Short reach falls off a cliff: shotguns, missiles and Inferno only count at 10 m; rifles and MGs fade by 60 m (spread).
- Steady at every distance: Laser (low: 2.7 LT / 5.1 HV), Mortar (15-18), Orbital (13-17, strafing barely helps), Patience (~8.7 still).
- A strafing target halves snipers past 60 m (13 -> 5 HV at 110 m, 14 -> 3 at 180 m) and zeroes Patience past 60 m; the Mortar loses most of its damage up close against one (18 -> 5 at 10 m: it lands where the target was).
- Odd: ROCKET LT ~3 DPS and erratic (0.1 at 30 m still, 0 at 60 m strafing) -- worth a look; SWARM HV only ~3-4 DPS at any range.
