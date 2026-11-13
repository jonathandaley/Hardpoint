"""Red/green self-check for transform_desync's match-end cut (T419).
Run: python3 -m tools.oracles.test_transform_desync
"""
from . import base, transform_desync


def _log(role, xs, peer, events=None):
    rows = [{"tick": t, "mech_id": "Mech_1_0", "owner": 7, "peer": peer, "pos": [x, 0.0, 0.0],
             "rot_local": [0, 0, 0, 1], "rot_global": [0, 0, 0, 1], "scale": 1.0} for t, x in enumerate(xs)]
    return base.PeerLog(role, rows, events or [])


def _v(server_xs, client_xs, end=None):
    ev = [{"tick": end, "type": "match_end", "mech_id": "", "payload": {}}] if end is not None else []
    ctx = {"primary": {"server": _log("server", server_xs, 1, ev), "client_1": _log("client_1", client_xs, 7)},
           "thresholds": {}}
    return transform_desync.run(ctx)["verdict"]


def main():
    walk = [0.05 * t for t in range(200)]
    stop_at_100 = [0.05 * min(t, 100) for t in range(200)]
    # the server's match ended at 100 and froze the mech; the client kept predicting: not a desync
    assert _v(stop_at_100, walk, end=100) == base.PASS, "post-match-end prediction judged"
    # the same divergence with no match end is a desync
    assert _v(stop_at_100, walk) == base.FAIL, "a real freeze went unseen"
    # a divergence well before the match end still fails
    early = [0.05 * min(t, 40) for t in range(200)]
    assert _v(early, walk, end=150) == base.FAIL, "a desync before the match end went unseen"
    print("test_transform_desync: OK")


if __name__ == "__main__":
    main()
