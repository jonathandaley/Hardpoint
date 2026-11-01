"""Red/green self-check for interp_smoothness (T150).
Run: python3 -m tools.oracles.test_interp_smoothness
"""
from . import base, interp_smoothness


def _log(role, positions, peer):
    return base.PeerLog(role, [{"tick": t, "mech_id": "Mech_0_0", "owner": 1, "peer": peer, "pos": [x, 0.0, 0.0]}
                               for t, x in enumerate(positions)], [])


def _v(client_positions):
    server = _log("server", [0.1 * t for t in range(120)], 1)
    return interp_smoothness.run({"primary": {"server": server, "client_1": _log("client_1", client_positions, 7)},
                                  "thresholds": {}})["verdict"]


def main():
    assert _v([0.1 * t for t in range(120)]) == base.PASS, "smooth"
    assert _v([0.1 * max(0, t - 6) for t in range(120)]) == base.PASS, "smooth but delayed"
    assert _v([0.1 * (t - t % 3) for t in range(120)]) == base.FAIL, "20 Hz steps on a 60 Hz tick"
    assert _v([0.1 * t if t < 60 else 6.0 for t in range(120)]) == base.FAIL, "frozen half the time"
    # B56: client loaded 40 ticks before the match went live; first frames after live lag by the
    # interp delay. Warm-up counts from live, not from the client's first tick.
    srv = [0.0] * 40 + [0.1 * t for t in range(60)]
    late = [0.0] * 55 + [0.1 * t for t in range(45)]
    ctx = {"primary": {"server": _log("server", srv, 1), "client_1": _log("client_1", late, 7)}, "thresholds": {}}
    assert interp_smoothness.run(ctx)["verdict"] == base.FAIL, "no live tick known: onset lag counts"
    assert sum(interp_smoothness.stall_ratios(ctx["primary"]["server"], ctx["primary"]["client_1"], 0.02,
                                              live=40)["Mech_0_0"][1:]) == 0, "warm-up from live hides onset lag"
    print("test_interp_smoothness: ok")


if __name__ == "__main__":
    main()
