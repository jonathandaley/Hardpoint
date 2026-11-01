"""Red/green self-check for bot_takeover (T153).
Run: python3 -m tools.oracles.test_bot_takeover
"""
import os
import tempfile

from . import base, bot_takeover


def _v(xs, hp=100.0, left=True):
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "server.log"), "w") as f:
        f.write("[Harness] peer_disconnected id=7 at sync tick 100\n" if left else "")
    snaps = [{"tick": t, "mech_id": "Mech_1_0", "owner": 7, "pos": [x, 0.0, 0.0], "health": hp}
             for t, x in enumerate(xs)]
    return bot_takeover.run({"run_dir": d, "primary": {"server": base.PeerLog("server", snaps, [])},
                             "thresholds": {}})["verdict"]


def main():
    assert _v([0.0] * 100 + [0.05 * t for t in range(700)]) == base.PASS, "bot walks off"
    assert _v([0.0] * 800) == base.FAIL, "mech frozen after its pilot left"
    assert _v([0.0] * 800, hp=0.0) == base.PASS, "dead mech needs no bot"
    assert _v([0.0] * 650) == base.PASS, "left 550 ticks before the run ended: end-of-run leaver, not judged"
    assert _v([0.0] * 800, left=False) == base.SKIP
    # killed client: no disconnect line; its log ends at tick 100 (T167)
    d = tempfile.mkdtemp()
    open(os.path.join(d, "server.log"), "w").close()
    with open(os.path.join(d, "client_1.log"), "w") as f:
        f.write("[Harness] input override done for client (mech Mech_1_0, match 1); x\n[Harness] action kill_client (client_1)\n")
    for xs, want in (([0.0] * 1200, base.FAIL), ([0.0] * 400 + [0.05 * t for t in range(800)], base.PASS)):
        snaps = [{"tick": t, "mech_id": "Mech_1_0", "owner": 7, "pos": [x, 0.0, 0.0], "health": 100.0} for t, x in enumerate(xs)]
        client = base.PeerLog("client_1", snaps[:101], [])
        got = bot_takeover.run({"run_dir": d, "thresholds": {},
                                "primary": {"server": base.PeerLog("server", snaps, []), "client_1": client}})["verdict"]
        assert got == want, ("killed client", want, got)
    print("test_bot_takeover: ok")


if __name__ == "__main__":
    main()
