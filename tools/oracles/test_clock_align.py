"""Self-check for T151 wall-clock tick alignment in base.load_run.
Run: python3 -m tools.oracles.test_clock_align
"""
import json
import os
import tempfile

from . import base, health_desync


def _write(d, role, start_unix, hp_drop_at_unix, n=300, peer=1):
    with open(os.path.join(d, role + ".jsonl"), "w") as f:
        for t in range(n):
            u = start_unix + t * 1000 // 60
            f.write(json.dumps({"tick": t, "mech_id": "Mech_0_0", "owner": 1, "peer": peer, "unix_ms": u,
                                "health": 135.0 if u >= hp_drop_at_unix else 175.0}) + "\n")


def main():
    d = tempfile.mkdtemp()
    # client's tick clock started 56 ticks (~0.93 s) after the server's; the hit lands at one wall time
    _write(d, "server", 1_000_000, 1_002_000)
    _write(d, "client_1", 1_000_933, 1_002_016, peer=7)  # sees the HP drop 1 tick later (latency)
    run = base.load_run(d)
    assert run["client_1"].offset == 56, run["client_1"].offset
    assert run["client_1"].snaps[0]["tick_local"] == 0 and run["client_1"].snaps[0]["tick"] == 56
    ctx = {"primary": run, "thresholds": {}}
    assert health_desync.run(ctx)["verdict"] == base.PASS, "aligned by wall clock: no desync"
    for s in run["client_1"].snaps:  # undo the alignment: same data on raw tick numbers
        s["tick"] = s["tick_local"]
    raw = {"server": run["server"], "client_1": base.PeerLog("client_1", run["client_1"].snaps, [])}
    assert health_desync.run({"primary": raw, "thresholds": {}})["verdict"] == base.FAIL, \
        "raw tick pairing sees a fake 56-tick HP gap"
    old = tempfile.mkdtemp()  # pre-T151 logs: no unix_ms -> offset 0
    for role in ("server", "client_1"):
        with open(os.path.join(old, role + ".jsonl"), "w") as f:
            f.write(json.dumps({"tick": 3, "mech_id": "M", "owner": 1, "peer": 1, "health": 1.0}) + "\n")
    assert base.load_run(old)["client_1"].offset == 0
    print("test_clock_align: ok")


if __name__ == "__main__":
    main()
