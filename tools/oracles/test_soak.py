"""Red/green self-check for the soak oracle (T152). Run: python3 -m tools.oracles.test_soak"""
import json
import os
import tempfile

import math

from . import base, soak


def _run(server_log, snaps=None, stats=None):
    d = tempfile.mkdtemp()
    open(os.path.join(d, "server.log"), "w").write(server_log)
    json.dump({"net": {"profile": "bad", "stats": stats or {}}}, open(os.path.join(d, "meta.json"), "w"))
    snaps = snaps or [{"tick": t, "mech_id": "M", "pos": [0.0, 0.0, float(t) / 10], "vel": [0.0, 0.0, 6.0],
                       "health": 100.0} for t in range(0, 600)]
    return soak.run({"run_dir": d, "primary": {"server": base.PeerLog("server", snaps, [])}, "thresholds": {}})


def _perf(orphans=(0, 0, 0), objects=(4000, 4000, 4000), ms=(2.0, 3.0, 4.0)):
    return "".join("[Harness] perf tick=%d phys_ms=%.1f objects=%d nodes=1700 orphans=%d mem=50000000\n"
                   % (i * 600, m, o, r) for i, (r, o, m) in enumerate(zip(orphans, objects, ms)))


def main():
    ended = "[Harness] match ended at sync tick 590\n"
    assert _run(_perf() + ended)["verdict"] == base.PASS
    assert _run(_perf())["field"] == "softlock", "no match end = softlock"
    assert _run(_perf(orphans=(0, 0, 300)) + ended)["field"] == "orphans", "orphan leak"
    assert _run(_perf(objects=(4000, 4000, 6000)) + ended)["field"] == "objects", "object growth"
    assert _run(_perf(ms=(30.0, 30.0, 30.0)) + ended)["field"] == "phys_ms", "median over budget"
    stuck = [{"tick": t, "mech_id": "M", "pos": [0.0, 0.0, 0.0], "vel": [0.0, 0.0, 6.0], "health": 100.0}
             for t in range(600)]
    assert _run(_perf() + ended, snaps=stuck)["field"] == "stuck", "pushing but not moving"
    loop = [{"tick": t, "mech_id": "M", "pos": [math.sin(t / 30.0), 0.0, 0.0], "vel": [0.0, 0.0, 1.5],
             "health": 100.0} for t in range(600)]
    assert _run(_perf() + ended, snaps=loop)["verdict"] == base.PASS, "out and back is not stuck (B55)"
    assert _run(_perf() + ended, stats={"s2c_bytes": 10 ** 9, "clients": 1})["field"] == "bandwidth"
    assert _run("no perf here\n")["verdict"] == base.SKIP
    print("test_soak: ok")


if __name__ == "__main__":
    main()
