"""profile_parity oracle (T154, V36): every peer applies the same match result
to its own profile with the T71 formula (Game._update_mp_profile), once per
match, and saves it.

Per peer log: `[Harness] profile_after match=N team=T elo=E xp=X coins=C level=L`
and `[Arena] MP match over. Team W wins.`; starting profile = scenario
peers.<role>.profile (default elo 1000, xp 0, coins 0). For match N each peer's
expected result is recomputed from the PRE-match values of every peer (match 1:
seeds; match N: the logged values after N-1): opponents = peers on the other
team (none -> bot ELO 1000). FAILs on a peer that disagrees on the winner,
misses a match, or ends up with other numbers; profile.cfg must hold the last.
"""
import glob
import math
import os
import re

from . import base

NAME = "profile_parity"
_K, _BOT_ELO = 32, 1000
_AFTER = re.compile(r"\[Harness\] profile_after match=(\d+) team=(-?\d+) elo=(-?\d+) xp=(-?\d+) coins=(-?\d+)")
_WIN = re.compile(r"\[Arena\] MP match over\. Team (\d+) wins\.")


def _gd_round(x):  # GDScript roundi: half away from zero
    return int(math.copysign(math.floor(abs(x) + 0.5), x))


def expected(pre, opp_elos, won):
    """(elo, xp, coins) after one match, as Game._update_mp_profile (no skills)."""
    opp = opp_elos or [_BOT_ELO]
    r = 1.0 if won else 0.0
    d = sum(_K * (r - 1.0 / (1.0 + 10 ** ((o - pre["elo"]) / 400.0))) for o in opp) / len(opp)
    avg = int(sum(opp) / len(opp))
    ratio = avg / max(1, pre["elo"])
    xp = min(200, max(25, _gd_round(50 * ratio))) if won else min(50, max(5, _gd_round(15 * ratio)))
    return {"elo": max(100, pre["elo"] + _gd_round(d)), "xp": pre["xp"] + xp, "coins": pre["coins"] + (75 if won else 20)}


def _cfg(path):
    out = {}
    for line in open(path, errors="replace"):
        m = re.match(r"(\w+)=(-?\d+)\s*$", line.strip())
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def run(ctx):
    run_dir = ctx.get("run_dir") or ""
    peers_cfg = (ctx.get("scenario") or {}).get("peers", {})
    logs = {}
    for path in sorted(glob.glob(os.path.join(run_dir, "*.log"))):
        role = os.path.basename(path)[: -len(".log")]
        if role in peers_cfg:
            logs[role] = open(path, errors="replace").read()
    after = {r: {int(m.group(1)): (int(m.group(2)), {"elo": int(m.group(3)), "xp": int(m.group(4)), "coins": int(m.group(5))})
                 for m in _AFTER.finditer(t)} for r, t in logs.items()}
    wins = {r: [int(w) for w in _WIN.findall(t)] for r, t in logs.items()}
    if not any(after.values()):
        return base.verdict(NAME, base.SKIP, note="no match ended")
    n_matches = max(max(a) for a in after.values() if a)
    for r, w in wins.items():
        if len(w) != n_matches or w != wins.get("server", w):
            return base.verdict(NAME, base.FAIL, peer=r, note="%s saw winners %s, server %s" % (r, w, wins.get("server")))
    pre = {r: {"elo": 1000, "xp": 0, "coins": 0, **{k: int(v) for k, v in peers_cfg[r].get("profile", {}).items()
                                                    if k in ("elo", "xp", "coins")}} for r in logs}
    for n in range(1, n_matches + 1):
        if any(n not in after[r] for r in logs):
            missing = [r for r in logs if n not in after[r]]
            return base.verdict(NAME, base.FAIL, note="match %d: no profile update on %s" % (n, missing))
        team = {r: after[r][n][0] for r in logs}
        for r in logs:
            opp = [pre[o]["elo"] for o in logs if team[o] != team[r]]
            want = expected(pre[r], opp, wins[r][n - 1] == team[r])
            got = after[r][n][1]
            if got != want:
                return base.verdict(NAME, base.FAIL, peer=r, field="profile",
                                    note="match %d: %s has %s, formula from pre-match %s gives %s (opp ELO %s)"
                                         % (n, r, got, pre[r], want, opp))
        pre = {r: after[r][n][1] for r in logs}
    for r in logs:
        m = re.search(r"\[Harness\] user_data_dir=(\S+)", logs[r])
        cfg_path = os.path.join(m.group(1), "profile.cfg") if m else ""
        if not os.path.exists(cfg_path):
            return base.verdict(NAME, base.FAIL, peer=r, note="%s never saved profile.cfg" % r)
        saved = _cfg(cfg_path)
        if any(saved.get(k) != pre[r][k] for k in ("elo", "xp", "coins")):
            return base.verdict(NAME, base.FAIL, peer=r, note="%s profile.cfg %s != last result %s" % (r, saved, pre[r]))
    return base.verdict(NAME, base.PASS, note="%d match(es): every peer's ELO/XP/coins follow the formula, saved"
                                              % n_matches)
