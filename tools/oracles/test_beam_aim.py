"""Red/green self-check for the beam_aim oracle (T142).
Run: python3 -m tools.oracles.test_beam_aim
"""
from . import base, beam_aim


def _ctx(pairs):
    ev = [{"tick": 100 + i, "type": "beam_check", "mech_id": "Mech_1_0",
           "payload": {"server_hit": s, "local_hit": l}} for i, (s, l) in enumerate(pairs)]
    return {"primary": {"server": base.PeerLog("server", [], []),
                        "client_1": base.PeerLog("client_1", [], ev)}, "thresholds": {}}


def main():
    assert beam_aim.run(_ctx([([1, 2, 3], [1, 2, 3.1])] * 5))["verdict"] == base.PASS
    v = beam_aim.run(_ctx([([1, 2, 3], [1, 2, 3])] * 4 + [([1, 2, 3], [4, 2, 3])]))
    assert v["verdict"] == base.FAIL and v["magnitude"] == 3.0, ("3 m miss must fail", v)
    assert beam_aim.run(_ctx([]))["verdict"] == base.FAIL, "no checks = vacuous, must fail"
    print("test_beam_aim: ok")


if __name__ == "__main__":
    main()
