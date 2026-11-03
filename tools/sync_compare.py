#!/usr/bin/env python3
"""M1 comparison driver for the MP autodebug harness.

Loads one run directory (the peer snapshot/event logs written by
run_scenario.py), dispatches the oracles named by the scenario, and aggregates
their verdicts into a single machine-readable PASS/FAIL report. With
--baseline-run, the determinism oracle compares the two runs' server streams.

Usage:
    sync_compare.py <scenario.json> <run_dir> [--baseline-run <dir>]
                    [--oracle NAME ...] [--json] [--quiet]

Aggregate verdict is FAIL if any oracle FAILs, else PASS (SKIPs are non-fatal).
Exit 0 = PASS, 1 = FAIL, 2 = error.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from oracles import (  # noqa: E402
    base, determinism, transform_desync, health_desync, lock_target, team_assignment,
    crash_scan, rpc_integrity, event_sidefx, ammo_desync, beacon_desync, spawn_join,
    friendly_fire, prediction_recon, hit_confirm, active_set_desync, reload_desync,
    aim_desync, input_delivery, beam_aim, log_flood, peer_closed, scene_routes, lobby_roster,
    hud_layout, world_invariants, interp_smoothness, latency_recovery, rpc_modes, fair_start, soak, menu_flow, bot_takeover, peer_drop, profile_parity, loop_audio,
    dedicated,
)

# Registry of oracle modules. Add modules here as they land.
ORACLES = {
    determinism.NAME: determinism,
    transform_desync.NAME: transform_desync,
    health_desync.NAME: health_desync,
    lock_target.NAME: lock_target,
    team_assignment.NAME: team_assignment,
    crash_scan.NAME: crash_scan,
    rpc_integrity.NAME: rpc_integrity,
    event_sidefx.NAME: event_sidefx,
    ammo_desync.NAME: ammo_desync,
    beacon_desync.NAME: beacon_desync,
    spawn_join.NAME: spawn_join,
    friendly_fire.NAME: friendly_fire,
    prediction_recon.NAME: prediction_recon,
    hit_confirm.NAME: hit_confirm,
    active_set_desync.NAME: active_set_desync,
    reload_desync.NAME: reload_desync,
    aim_desync.NAME: aim_desync,
    input_delivery.NAME: input_delivery,
    beam_aim.NAME: beam_aim,
    log_flood.NAME: log_flood,
    peer_closed.NAME: peer_closed,
    scene_routes.NAME: scene_routes,
    lobby_roster.NAME: lobby_roster,
    hud_layout.NAME: hud_layout,
    world_invariants.NAME: world_invariants,
    interp_smoothness.NAME: interp_smoothness,
    latency_recovery.NAME: latency_recovery,
    rpc_modes.NAME: rpc_modes,
    fair_start.NAME: fair_start,
    soak.NAME: soak,
    menu_flow.NAME: menu_flow,
    bot_takeover.NAME: bot_takeover,
    peer_drop.NAME: peer_drop,
    profile_parity.NAME: profile_parity,
    loop_audio.NAME: loop_audio,
    dedicated.NAME: dedicated,
}


def _thresholds(scenario, run_dir):
    """Scenario thresholds, with T151 impaired-network windows underneath when
    the run went through a lossy/jittery proxy profile (meta.json "net")."""
    th = dict(scenario.get("thresholds", {}))
    net = None
    for d in (run_dir, os.path.dirname(run_dir.rstrip("/"))):  # T163: match<n>/ uses the run's meta
        try:
            with open(os.path.join(d, "meta.json")) as f:
                net = (json.load(f).get("net") or {}).get("profile")
            break
        except (OSError, ValueError):
            pass
    if isinstance(net, str):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "mp_harness"))
        import netem_proxy
        net = netem_proxy.resolve(net)
    if isinstance(net, dict) and (net.get("loss") or net.get("jitter_ms") or net.get("outage")
                                  or net.get("latency_ms", 0) > 5):
        # relaxations win over a scenario's clean-link tuning: take the more lenient (larger) value
        th = {**th, **{k: max(v, th.get(k, v)) for k, v in base.IMPAIRED_NET_THRESHOLDS.items()}}
    return th


def select_oracles(scenario, override):
    if override:
        names = override
    else:
        names = scenario.get("oracles") or list(ORACLES)
        # T149/T150: every scenario (SKIP if n/a); T156 review runs (a rendered peer runs ~4x slow) opt out
        for auto in () if scenario.get("review") else ("world_invariants", "interp_smoothness", "fair_start", "peer_drop",
                                                       "prediction_recon"):  # T205
            if auto not in names:
                names = list(names) + [auto]
    known, unknown = [], []
    for n in names:
        (known if n in ORACLES else unknown).append(n)
    return known, unknown


def run(scenario_path, run_dir, baseline_dir, override, want_json, quiet):
    with open(scenario_path) as f:
        scenario = json.load(f)
    primary = base.load_run(run_dir)
    if not primary:
        print("ERROR: no <role>.jsonl snapshot logs in %s" % run_dir, file=sys.stderr)
        return 2, None
    baseline = base.load_run(baseline_dir) if baseline_dir else None

    ctx = {
        "primary": primary,
        "baseline": baseline,
        "scenario": scenario,
        "thresholds": _thresholds(scenario, run_dir),
        "run_dir": os.path.abspath(run_dir),
    }
    names, unknown = select_oracles(scenario, override)
    results = [ORACLES[n].run(ctx) for n in names]
    # T204: a scenario naming an unregistered oracle (new module not added to ORACLES,
    # or a typo) used to warn on stderr and skip -- the guard silently never ran
    results += [base.verdict(n, base.FAIL, note="unknown oracle (not in the sync_compare registry)")
                for n in unknown]
    # M2.2: strict xfail. A scenario lists known-open bugs in "expect_fail";
    # their FAIL becomes non-fatal XFAIL, and a PASS becomes fatal XPASS so the
    # marker gets removed the moment the bug is actually fixed.
    expect_fail = set(scenario.get("expect_fail", []))
    for r in results:
        if r["oracle"] in expect_fail:
            if r["verdict"] == base.FAIL:
                r["verdict"] = "XFAIL"
            elif r["verdict"] == base.PASS:
                r["verdict"] = "XPASS"
                r["note"] = "unexpected pass; remove from expect_fail. " + r.get("note", "")
    failed = any(r["verdict"] in (base.FAIL, "XPASS") for r in results)
    report = {
        "scenario": scenario.get("name"),
        "run_dir": os.path.abspath(run_dir),
        "baseline_run": os.path.abspath(baseline_dir) if baseline_dir else None,
        "peers": sorted(primary),
        "verdict": base.FAIL if failed else base.PASS,
        "oracles": results,
    }

    if want_json:
        print(json.dumps(report, indent=2))
    elif not quiet:
        print("scenario=%s  peers=%s  -> %s" % (report["scenario"], ",".join(report["peers"]), report["verdict"]))
        for r in results:
            line = "  [%-4s] %-16s %s" % (r["verdict"], r["oracle"], r.get("note", ""))
            print(line)
            if r["verdict"] == base.FAIL:
                det = {k: r[k] for k in ("mech_id", "field", "first_tick", "magnitude", "pattern", "peer") if k in r}
                if det:
                    print("           %s" % json.dumps(det))
    return (1 if failed else 0), report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    ap.add_argument("run_dir")
    ap.add_argument("--baseline-run", default=None,
                    help="second run dir for the determinism oracle")
    ap.add_argument("--oracle", action="append", default=None,
                    help="run only these oracle(s); repeatable")
    ap.add_argument("--json", action="store_true", help="emit the full verdict report as JSON")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()
    try:
        rc, _ = run(args.scenario, args.run_dir, args.baseline_run, args.oracle, args.json, args.quiet)
        return rc
    except (OSError, json.JSONDecodeError, KeyError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
