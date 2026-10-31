"""Red/green self-check for the input_delivery oracle (T158).
Run: python3 -m tools.oracles.test_input_delivery
"""
from . import base, input_delivery


def _ev(tick, typ, action, slot=-1, mech="Mech_1_0"):
    return {"tick": tick, "type": typ, "mech_id": mech, "payload": {"action": action, "slot": slot}}


def _ctx(client_events, server_events):
    snaps = [{"tick": 600, "mech_id": "Mech_1_0"}]  # run end comes from snapshots, not events
    return {"primary": {"server": base.PeerLog("server", snaps, server_events),
                        "client_1": base.PeerLog("client_1", snaps, client_events)},
            "thresholds": {}}


def main():
    presses = [_ev(61, "input_press", "reload"), _ev(120, "input_press", "reload"),
               _ev(301, "input_press", "slot", 1)]
    applied = [_ev(64, "input_applied", "reload"), _ev(123, "input_applied", "reload"),
               _ev(304, "input_applied", "slot", 1)]
    assert input_delivery.run(_ctx(presses, applied))["verdict"] == base.PASS
    v = input_delivery.run(_ctx(presses, applied[1:]))
    assert v["verdict"] == base.FAIL and v["magnitude"] == 1, ("lost press must fail", v)
    v = input_delivery.run(_ctx(presses, applied + [_ev(130, "input_applied", "reload")]))
    assert v["verdict"] == base.FAIL, ("double-applied press must fail", v)
    v = input_delivery.run(_ctx(presses, applied[:2] + [_ev(304, "input_applied", "slot", 2)]))
    assert v["verdict"] == base.FAIL, ("wrong slot must fail", v)
    late = presses + [_ev(560, "input_press", "ability")]
    assert input_delivery.run(_ctx(late, applied))["verdict"] == base.PASS, "press in tail window is ignored"
    bot = applied + [_ev(200, "input_applied", "reload", mech="Bot_9")]
    assert input_delivery.run(_ctx(presses, bot))["verdict"] == base.PASS, "mechs without presses are ignored"
    assert input_delivery.run(_ctx([], applied))["verdict"] == base.SKIP
    tail_ok = presses + [_ev(480, "input_press", "ability")]
    v = input_delivery.run(_ctx(tail_ok, applied))
    assert v["verdict"] == base.FAIL and v["field"] == "ability", ("press before tail, last event, still counts", v)
    print("test_input_delivery: ok")


if __name__ == "__main__":
    main()
