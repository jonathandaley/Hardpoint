"""Red/green self-check for world_invariants (T149).
Run: python3 -m tools.oracles.test_world_invariants
"""
from . import base, world_invariants


def _snap(**kw):
    s = {"tick": 5, "mech_id": "Mech_0_0", "pos": [1.0, 4.0, 2.0], "aim": [0.1, -0.3], "health": 100.0,
         "max_hp": 175.0, "ammo": {"0": 3}, "ammo_max": {"0": 5}}
    s.update(kw)
    return s


def _v(snaps=(), beacons=()):
    log = base.PeerLog("server", list(snaps), [], list(beacons))
    return world_invariants.run({"primary": {"server": log}, "thresholds": {}})["verdict"]


def main():
    ok_b = {"tick": 1, "beacon_id": "B1", "progress": 0.4, "owner_team": -1, "capturing_team": 0}
    assert _v([_snap()], [ok_b]) == base.PASS
    assert _v([_snap(pos=[1.0, float("nan"), 2.0])]) == base.FAIL, "NaN position"
    assert _v([_snap(health=-3.0)]) == base.FAIL, "negative health"
    assert _v([_snap(health=180.0)]) == base.FAIL, "health above max"
    assert _v([_snap(ammo={"0": 6})]) == base.FAIL, "ammo above magazine"
    assert _v([_snap(ammo={"0": -1})]) == base.FAIL, "negative ammo"
    assert _v([_snap(ammo={"0": 999}, ammo_max={"0": -1})]) == base.PASS, "infinite magazine"
    assert _v([_snap(pos=[0.0, -80.0, 0.0])]) == base.FAIL, "fell out of the world"
    assert _v([_snap()], [dict(ok_b, progress=1.3)]) == base.FAIL, "beacon progress > 1"
    assert _v([_snap()], [dict(ok_b, owner_team=7)]) == base.FAIL, "bad beacon team"
    old = _snap(); old.pop("max_hp"); old.pop("ammo_max")
    assert _v([old]) == base.PASS, "pre-T149 log without max fields"
    print("test_world_invariants: ok")


if __name__ == "__main__":
    main()
