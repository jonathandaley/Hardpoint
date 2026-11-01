"""Red/green self-check for loop_audio (T155). Run: python3 -m tools.oracles.test_loop_audio"""
from . import base, loop_audio


def _log(role, loops, hp=None, events=()):
    snaps = [{"tick": t, "mech_id": "Mech_1_0", "owner": 7, "loops": [0] if on else [],
              "health": (hp[t] if hp else 100.0), "pos": [0.0, 0.0, 0.0]} for t, on in enumerate(loops)]
    return base.PeerLog(role, snaps, list(events))


def _v(server, client, **kw):
    return loop_audio.run({"primary": {"server": server, "client_1": client}, "thresholds": {}, **kw})["verdict"]


def main():
    beam = [60 <= t < 200 for t in range(400)]
    lagged = [66 <= t < 215 for t in range(400)]
    assert _v(_log("server", beam), _log("client_1", lagged)) == base.PASS, "stops with the beam (lagged)"
    stuck = [t >= 66 for t in range(400)]
    assert _v(_log("server", beam), _log("client_1", stuck)) == base.FAIL, "client loop never stopped"
    dead = [100.0 if t < 150 else 0.0 for t in range(400)]
    both = [t >= 60 for t in range(400)]
    assert _v(_log("server", both, hp=dead), _log("client_1", both, hp=dead)) == base.FAIL, "loop on a dead mech"
    ended = [{"tick": 150, "type": "match_end"}]
    assert _v(_log("server", both, events=ended), _log("client_1", both)) == base.FAIL, "loop after match end"
    assert _v(_log("server", [False] * 400), _log("client_1", [False] * 400)) == base.SKIP
    print("test_loop_audio: ok")


if __name__ == "__main__":
    main()
