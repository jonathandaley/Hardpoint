#!/usr/bin/env python3
"""T539 (user 2026-11-20: "a sustained dps vs range vs accuracy one would be good"): every catalog weapon's
SUSTAINED DPS at 10 / 30 / 60 / 110 / 180 m against a still and a strafing target, measured in the engine by
tools/balance/dps_range.tscn (Elite bots aiming, everything that makes shots miss included; 60 s held, so
reloads count). Burst DPS: tools/weapon_table.py (assumes every hit lands).
  python3 tools/weapon_dps_range.py [-j 6] [--secs 60] [-r 3] > docs/WEAPON_DPS_RANGE.md
One run of a bot fight swings a lot (a bot that takes a while to engage, a jump): each cell is the MEDIAN of
-r runs. ~8 min a pass with -j 6 on the T3500.
"""
import argparse, concurrent.futures as cf, json, os, re, statistics, subprocess, tempfile

R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
GODOT = os.path.expanduser('~/bin/godot')
lobby = open(os.path.join(R, 'scripts/Lobby.gd')).read()
CAT = re.findall(r'\{"name": "([^"]+)",\s*"path": "(res://[^"]+)",\s*"long": "[^"]+",\s*"slot_size": (\d)\}', lobby)


def run(path, motion, secs):
    with tempfile.TemporaryDirectory(dir=os.path.join(R, 'build')) as xdg:  # never the user's own profile
        out = subprocess.run([GODOT, '--headless', '--path', R, 'res://tools/balance/dps_range.tscn',
                              '--fixed-bots=Pegasus', '--', 'weapon=' + path, 'motion=' + motion, 'secs=%d' % secs],
                             capture_output=True, text=True, timeout=secs * 20 + 300,
                             env=dict(os.environ, XDG_DATA_HOME=xdg)).stdout
    return [json.loads(l[6:]) for l in out.splitlines() if l.startswith('[dps] ')]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('-j', type=int, default=6)
    ap.add_argument('--secs', type=int, default=60)
    ap.add_argument('-r', type=int, default=3)
    a = ap.parse_args()
    jobs = [(n, p, int(s), m) for _ in range(a.r) for n, p, s in CAT for m in ('still', 'strafe')]
    runs, out = {}, set()
    with cf.ThreadPoolExecutor(a.j) as ex:
        for (n, p, s, m), rows in zip(jobs, ex.map(lambda j: run(j[1], j[3], a.secs), jobs)):
            for r in rows:
                runs.setdefault((n, m, r['d']), []).append(r['dmg'] / r['secs'])
                if r.get('out'):
                    out.add((n, r['d']))
    res = {k: statistics.median(v) for k, v in runs.items()}
    dists = [10.0, 30.0, 60.0, 110.0, 180.0]
    print('# Weapon sustained DPS vs range (T539)\n')
    print('Measured in the engine (`python3 tools/weapon_dps_range.py`): an Elite bot holds the trigger %d s at a '
          'mech-sized target (no shields, no skills / powerups) at each distance; reloads, spread, falloff, '
          'travel time, splash and lock time all count. Each cell: **still** / strafing target (walks left / '
          'right across the line of fire, turning every 1.5 s); the median of %d runs. Blank = past 95%% of the '
          'weapon\'s range (bots don\'t fire there); "-" = no run.\n' % (a.secs, a.r))
    for slot, title in ((0, 'Light'), (1, 'Heavy')):
        print('## %s\n' % title)
        print('| weapon | ' + ' | '.join('%d m' % d for d in dists) + ' |')
        print('|---|' + '--:|' * len(dists))
        for n, p, s in CAT:
            if int(s) != slot:
                continue
            cells = []
            for d in dists:
                st, sf = res.get((n, 'still', d)), res.get((n, 'strafe', d))
                if (n, d) in out:
                    cells.append('')
                else:
                    cells.append('-' if st is None else ('**%.1f** / %.1f' % (st, sf if sf is not None else 0.0)))
            print('| %s | %s |' % (n, ' | '.join(cells)))
        print()


if __name__ == '__main__':
    main()
