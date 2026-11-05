"""prediction_recon oracle (T205): the owning client's predicted mech stays close to
the server's authoritative one.

Each snapshot a predicting client compares the server's position with its own record
for the same input tick and logs `pred_recon` {err, snap} (Mech._reconcile). FAIL
when, for any client, the 95th-percentile error exceeds `pred_p95_m` or more than
`pred_snap_frac` of reconciliations had to snap (error over Mech.PRED_SNAP_M):
prediction diverging from the server (movement code that differs, input applied on
the wrong ticks, broken matching) shows up as both. SKIP with no predicting client.
Measured 2026-11-03: loopback p95 <= 0.06 m (default 0.15), `bad` profile p95 <= 0.39 m
(impaired default 0.6), 0 snaps.
"""
from . import base

NAME = "prediction_recon"
DEFAULTS = {"pred_p95_m": 0.15, "pred_snap_frac": 0.02}
MIN_SAMPLES = 20  # 1 s of snapshots: judge only runs long enough to settle  # impaired links: base.IMPAIRED_NET_THRESHOLDS
# T268 (B105): the first second after the first reconciliation is start-up alignment --
# on the `bad` link (loss, 80 ms +- 30) the first inputs can be lost and the error starts
# near 0.9 m, easing out (no snap) within ~1 s. In a short run (two_matches: ~70
# reconciliations) those few samples alone decided p95 (flaky, 1-in-6 to 1-in-4). Judge
# settled prediction; a divergence that persists still fails.
WARMUP_TICKS = 60


def run(ctx):
    th = {**DEFAULTS, **ctx.get("thresholds", {})}
    worst, seen = None, 0
    for role, log in sorted(ctx["primary"].items()):
        recs = [e for e in log.events if e.get("type") == "pred_recon"]
        t0 = min((int(e.get("tick", 0)) for e in recs), default=0)
        evs = [e.get("payload", {}) for e in recs if int(e.get("tick", 0)) >= t0 + WARMUP_TICKS]
        if len(evs) < MIN_SAMPLES:
            continue  # a few start-up reconciliations (host_crash: 7) are all transient
        seen += 1
        errs = sorted(float(p.get("err", 0.0)) for p in evs)
        p95 = errs[min(len(errs) - 1, int(len(errs) * 0.95))]
        snaps = sum(1 for p in evs if p.get("snap"))
        if p95 > th["pred_p95_m"] or snaps > th["pred_snap_frac"] * len(evs):
            v = base.verdict(NAME, base.FAIL, peer=role,
                             note="p95 error %.2f m (max %.2f), %d/%d snapped" % (p95, errs[-1], snaps, len(evs)))
            if worst is None:
                worst = v
    if worst is not None:
        return worst
    if not seen:
        return base.verdict(NAME, base.SKIP, note="no predicting client with >= %d reconciliations" % MIN_SAMPLES)
    return base.verdict(NAME, base.PASS, note="%d predicting client(s) within p95 %.2f m, snaps <= %.0f%%"
                        % (seen, th["pred_p95_m"], th["pred_snap_frac"] * 100))
