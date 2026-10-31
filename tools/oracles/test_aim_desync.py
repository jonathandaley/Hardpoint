"""Red/green self-check for the aim_desync oracle (T140).
Run: python3 -m tools.oracles.test_aim_desync
"""
from . import aim_desync, base

MID, CID = "Mech_1_0", 7


def _ctx(client_aims, server_aims):
    """Per-tick aim lists ([yaw, pitch]) for the client's own mech on each peer."""
    def snaps(aims, peer):
        return [{"tick": t, "mech_id": MID, "owner": CID, "peer": peer, "aim": a}
                for t, a in enumerate(aims)]
    server = base.PeerLog("server", snaps(server_aims, 1), [])
    client = base.PeerLog("client_1", snaps(client_aims, CID), [])
    return {"primary": {"server": server, "client_1": client}, "thresholds": {}}


def _turn_then_hold(final_yaw, lag=0, pitch=-0.3):
    """60 ticks turning toward final_yaw (server may lag), then 60 ticks held."""
    turn = [[final_yaw * min(1.0, max(0, t - lag) / 60.0), pitch] for t in range(60)]
    return turn + [[final_yaw, pitch]] * 60


def main():
    same = _turn_then_hold(0.9)
    assert aim_desync.run(_ctx(same, same))["verdict"] == base.PASS
    lagged = _turn_then_hold(0.9, lag=5)
    assert aim_desync.run(_ctx(same, lagged))["verdict"] == base.PASS, "lag during a turn is not desync"
    v = aim_desync.run(_ctx(same, _turn_then_hold(0.85)))
    assert v["verdict"] == base.FAIL and v["field"] == "yaw", ("settled yaw offset must fail", v)
    v = aim_desync.run(_ctx(same, _turn_then_hold(0.9, pitch=-0.29)))
    assert v["verdict"] == base.FAIL and v["field"] == "pitch", ("settled pitch offset must fail", v)
    wrap = _turn_then_hold(3.14159)
    wrapped = [[a[0] - 6.28318 if t >= 60 else a[0], a[1]] for t, a in enumerate(wrap)]
    assert aim_desync.run(_ctx(wrap, wrapped))["verdict"] == base.PASS, "yaw wrap at pi is not desync"
    assert aim_desync.run(_ctx([[0.0, -0.3]] * 10, [[0.0, -0.3]] * 10))["verdict"] == base.SKIP, \
        "never settled long enough = no evidence"
    print("test_aim_desync: ok")


if __name__ == "__main__":
    main()
