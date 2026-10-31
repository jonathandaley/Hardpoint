"""Red/green self-check for hud_layout (T147). Run: python3 -m tools.oracles.test_hud_layout"""
import json
import os
import tempfile

from . import base, hud_layout


def _icons(xs, w=36, h=22):
    return [{"path": "WeaponHUD/Icon%d" % (i + 1), "class": "TextureRect", "rect": [x, 320, w, h], "text": ""}
            for i, x in enumerate(xs)]


def _run(server_controls, client_controls):
    d = tempfile.mkdtemp()
    for role, cs in (("server", server_controls), ("client_1", client_controls)):
        with open(os.path.join(d, role + ".hud.jsonl"), "w") as f:
            f.write(json.dumps({"tick": 60, "viewport": [640, 360], "controls": cs}) + "\n")
    return hud_layout.run({"run_dir": d})["verdict"]


def main():
    ok = _icons([516, 556, 596])
    assert _run(ok, ok) == base.PASS
    assert _run(ok, _icons([516, 530, 544])) == base.FAIL, "client icons squashed together"
    assert _run(ok, _icons([516, 556, 596], w=12)) == base.FAIL, "shrunk icons"
    assert _run(ok, ok + [{"path": "AmmoLabel", "class": "Label", "rect": [600, 350, 80, 20], "text": "x"}]) == base.FAIL, \
        "off-screen control"
    assert _run(ok, _icons([500, 540, 580])) == base.FAIL, "client differs from server"
    assert hud_layout.run({"run_dir": tempfile.mkdtemp()})["verdict"] == base.SKIP
    print("test_hud_layout: ok")


if __name__ == "__main__":
    main()
