"""V45 self-check for the hit_confirm oracle: peer tick clocks are independent
frame counters, so a confirm stamped 1 tick before its server hit is a clock
skew, not a lost RPC (T136). Run: python3 -m tools.oracles.test_hit_confirm
"""
from . import base, hit_confirm


def _ctx(confirm_ticks, hit_tick=1281):
    server = base.PeerLog("server",
                          [{"tick": 0, "mech_id": "Mech_1_0", "owner": 7, "peer": 1}],
                          [{"tick": hit_tick, "type": "hit", "mech_id": "Mech_0_0",
                            "payload": {"src": "Mech_1_0"}}])
    client = base.PeerLog("client_1",
                          [{"tick": 0, "mech_id": "Mech_1_0", "owner": 7, "peer": 7}],
                          [{"tick": t, "type": "hit_confirm", "mech_id": "Mech_1_0"}
                           for t in confirm_ticks])
    return {"primary": {"server": server, "client_1": client}, "thresholds": {}}


def main():
    assert hit_confirm.run(_ctx([1281]))["verdict"] == base.PASS
    assert hit_confirm.run(_ctx([1280]))["verdict"] == base.PASS, "1-tick skew is not a lost confirm"
    assert hit_confirm.run(_ctx([1300]))["verdict"] == base.PASS
    assert hit_confirm.run(_ctx([]))["verdict"] == base.FAIL, "missing confirm must still fail"
    assert hit_confirm.run(_ctx([1270]))["verdict"] == base.FAIL, "confirm well before the hit is not a match"
    assert hit_confirm.run(_ctx([1320]))["verdict"] == base.FAIL, "confirm past the delay window"
    print("test_hit_confirm: ok")


if __name__ == "__main__":
    main()
