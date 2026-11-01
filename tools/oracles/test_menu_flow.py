"""Red/green self-check for menu_flow (T164).
Run: python3 -m tools.oracles.test_menu_flow
"""
import os
import tempfile

from . import base, menu_flow

PICK = '[Harness] menu_pick peer=%d max_hp=%d weapons=["res://scenes/weapons/%s.tscn"] mech=res://x.tres\n'
SPAWN = '[Harness] spawned owner=%d max_hp=%d weapons=["res://scenes/weapons/%s.tscn"] mech=Mech_0_0\n'


def _v(server, client):
    d = tempfile.mkdtemp()
    for role, text in (("server", server), ("client_1", client)):
        with open(os.path.join(d, role + ".log"), "w") as f:
            f.write(text)
    return menu_flow.run({"run_dir": d})


def main():
    spawned = SPAWN % (1, 700, "RifleHeavy") + SPAWN % (5, 500, "MachineGunLight")
    good = _v(PICK % (1, 700, "RifleHeavy") + spawned, PICK % (5, 500, "MachineGunLight") + spawned)
    assert good["verdict"] == base.PASS, good
    wrong = SPAWN % (1, 700, "RifleHeavy") + SPAWN % (5, 500, "RifleLight")
    assert _v(PICK % (1, 700, "RifleHeavy") + spawned, PICK % (5, 500, "MachineGunLight") + wrong)["verdict"] \
        == base.FAIL, "client shows the wrong weapon"
    assert _v(PICK % (1, 700, "RifleHeavy") + spawned, PICK % (5, 900, "MachineGunLight") + spawned)["verdict"] \
        == base.FAIL, "wrong mech (max_hp)"
    assert _v("[Harness] MENU FAIL (client): click on ReadyBtn at (1, 2) did not press it\n", "")["verdict"] \
        == base.FAIL, "stuck menu step"
    assert _v(PICK % (1, 700, "RifleHeavy"), "")["verdict"] == base.FAIL, "picked but never spawned"
    assert _v("", "")["verdict"] == base.SKIP
    print("test_menu_flow: ok")


if __name__ == "__main__":
    main()
