#!/usr/bin/env python3
"""T484 (HUMAN_FOUND 2026-11-18: "Make a table of DPS and range on all the weapons ... I want to see the
numbers."): every catalog weapon's per-shot damage, rate, burst DPS (trigger held, magazine full) and
sustained DPS (held for a minute: FIXED mags reload, REFILLING ones refill while firing), range, magazine,
lock. Every hit lands, splash on the same target, no pilot skills or powerups.
  python3 tools/weapon_table.py > docs/WEAPON_TABLE.md
"""
import re, os, sys

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..') + '/'
lobby = open(R + 'scripts/Lobby.gd').read()
cat = re.findall(r'\{"name": "([^"]+)",\s*"path": "res://([^"]+)",\s*"long": "([^"]+)",\s*"slot_size": (\d)\}', lobby)

def script_defaults(path, seen=None):
    s = open(R + path).read()
    d = {}
    m = re.search(r'^extends\s+"res://([^"]+)"', s, re.M)
    if m:
        d.update(script_defaults(m.group(1)))
    for name, val in re.findall(r'^@export var (\w+)\s*:\s*\w+\s*=\s*([^#\n]+)', s, re.M):
        d[name] = val.strip()
    for name, val in re.findall(r'^const ([A-Z_]+)\s*:?=\s*([0-9.]+)\s*(?:#|$)', s, re.M):
        d['const:' + name] = val
    return d

def scene_props(path):
    s = open(R + path).read()
    script = re.search(r'path="res://(scripts/[^"]+\.gd)"', s).group(1)
    d = script_defaults(script)
    root = s.split('[node name=')[1]
    root = root.split('\n[')[0]
    for line in root.split('\n')[1:]:
        m = re.match(r'(\w+) = (.+)$', line)
        if m and m.group(1) not in ('script',):
            d[m.group(1)] = m.group(2)
    return script.split('/')[-1][:-3], d

def f(d, k, default=0.0):
    v = d.get(k, default)
    try:
        return float(v)
    except (TypeError, ValueError):
        return float(default)

rows = []
for name, path, long_, slot in cat:
    cls, d = scene_props(path)
    dmg, rate, rng = f(d, 'damage'), f(d, 'fire_rate', 2.0), f(d, 'range', 100.0)
    mag, mtype = int(f(d, 'max_ammo', -1)), int(f(d, 'magazine_type', 0))
    reload_, refill = f(d, 'reload_time', 1.5), f(d, 'refill_rate', 5.0)
    lock = d.get('requires_lock', 'false') == 'true'
    per_shot = dmg
    note = ''
    rate_hi = rate
    if cls == 'Shotgun':
        n = int(f(d, 'pellet_count', 8))
        per_shot = n * f(d, 'damage_close', 18.0)
        note = '%d pellets: %.0f point blank -> %.0f at max range' % (n, per_shot, n * f(d, 'damage_far', 3.0))
    elif cls == 'MachineGun':
        rate = f(d, 'base_fire_rate', 4.0); rate_hi = f(d, 'max_fire_rate', 14.0)
        note = 'spins up %.0f -> %.0f shots/s (+%.0f/s held)' % (rate, rate_hi, f(d, 'rate_accel', 10.0))
    elif cls == 'ArcWeapon':
        note = 'x%.1f within %.0f m, x1 from %.0f m' % (f(d, 'const:CLOSE_MULT', 2.5), f(d, 'const:CLOSE_M', 10.0), rng * f(d, 'const:FAR_FRAC', 0.6))
    elif cls == 'Patience':
        lo, hi, ct = f(d, 'min_damage', 30), f(d, 'max_damage', 250), f(d, 'max_charge_time', 3.0)
        per_shot = hi; rate = 1.0 / (ct + 1.0 / max(rate, 0.01)); rate_hi = rate
        note = 'charge: %.0f -> %.0f over %.1f s (DPS at full charge)' % (lo, hi, ct)
    elif cls == 'Flamer':
        bd = f(d, 'burn_dps', 6.0)
        note = 'cone %.0f deg; + burn %.0f dps for %.0f s after' % (f(d, 'cone_deg', 11.0) * 2, bd, f(d, 'burn_s', 2.0))
    elif cls == 'Mortar':
        per_shot = dmg + f(d, 'splash_damage', 50.0)
        note = 'direct %.0f + splash %.0f (r %.0f m); lobbed' % (dmg, f(d, 'splash_damage', 50.0), f(d, 'splash_radius', 5.0))
    elif cls == 'MissileLauncher':
        per_shot = dmg + f(d, 'splash_damage', 15.0)
        note = 'direct %.0f + splash %.0f (r %.0f m)' % (dmg, f(d, 'splash_damage', 15.0), f(d, 'splash_radius', 4.0))
    elif cls == 'OrbitalStrike':  # T522: one marked strike, 10 s later
        per_shot = dmg
        note = 'one strike %.0f at the centre -> %.0f at the rim (r %.0f m), lands 10 s after the mark; needs a lock' % (dmg, f(d, 'edge_damage', 120.0), f(d, 'strike_radius', 10.0))
    elif cls in ('AerialStrike', 'Swarm'):
        bc = int(f(d, 'burst_count', 20))
        per_shot = bc * (dmg + f(d, 'splash_damage', 1.6))
        note = 'salvo of %d (each %.0f + splash %.1f, r %.0f m) if all land' % (bc, dmg, f(d, 'splash_damage', 1.6), f(d, 'splash_radius', 8.0))
    burst = per_shot * rate
    burst_hi = per_shot * rate_hi
    if cls == 'Flamer':
        burst += f(d, 'burn_dps', 6.0); burst_hi = burst
    # sustained (holding the trigger for a minute)
    if mag <= 0:
        sus = burst_hi
    elif mtype == 0:  # FIXED: empty, reload, repeat
        r = rate_hi if cls == 'MachineGun' else rate
        cycle = mag / r + reload_
        sus = per_shot * mag / cycle + (f(d, 'burn_dps', 6.0) if cls == 'Flamer' else 0)
    else:  # REFILLING: refills while firing too
        r = rate_hi if cls == 'MachineGun' else rate
        sus = per_shot * min(r, refill) + (f(d, 'burn_dps', 6.0) if cls == 'Flamer' else 0)
    magtxt = '-' if mag <= 0 else ('%d / %.1fs reload' % (mag, reload_) if mtype == 0 else '%d / +%.2g per s' % (mag, refill))
    rows.append((long_, 'H' if slot == '1' else 'L', per_shot, rate, rate_hi, burst, burst_hi, sus, rng, magtxt, 'lock' if lock else '', note))

print('| weapon | slot | per shot | shots/s | DPS (burst) | DPS (sustained) | range m | magazine | lock | notes |')
print('|---|---|--:|--:|--:|--:|--:|---|---|---|')
for r in sorted(rows, key=lambda r: (r[1], -r[7])):
    rate_s = ('%.2g' % r[3]) if abs(r[3] - r[4]) < 1e-6 else '%.0f-%.0f' % (r[3], r[4])
    burst_s = '%.0f' % r[5] if abs(r[5] - r[6]) < 0.5 else '%.0f-%.0f' % (r[5], r[6])
    print('| %s | %s | %.0f | %s | %s | %.0f | %.0f | %s | %s | %s |' % (r[0], r[1], r[2], rate_s, burst_s, r[7], r[8], r[9], r[10], r[11]))
