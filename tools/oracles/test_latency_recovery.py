"""Red/green self-check for latency_recovery (T151). Run: python3 -m tools.oracles.test_latency_recovery"""
from . import base, latency_recovery


def _log(role, peer, hp_at_end, n=120):
    return base.PeerLog(role, [{"tick": t, "mech_id": "Mech_0_0", "owner": 1, "peer": peer, "pos": [0.0, 4.0, 0.0],
                                "health": hp_at_end if t > n - 50 else 175.0, "ammo": {"0": 3},
                                "lock_target": None, "eligible": None} for t in range(n)], [])


def main():
    ok = {"server": _log("server", 1, 135.0), "client_1": _log("client_1", 7, 135.0)}
    assert latency_recovery.run({"primary": ok, "thresholds": {}})["verdict"] == base.PASS
    stuck = {"server": _log("server", 1, 135.0), "client_1": _log("client_1", 7, 175.0)}
    v = latency_recovery.run({"primary": stuck, "thresholds": {}})
    assert v["verdict"] == base.FAIL and v["field"] == "health", ("missed HP change never recovered", v)
    print("test_latency_recovery: ok")


if __name__ == "__main__":
    main()
