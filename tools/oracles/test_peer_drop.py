"""Red/green self-check for peer_drop (T167). Run: python3 -m tools.oracles.test_peer_drop"""
import os
import tempfile

from . import base, peer_drop


def _v(lines, actions=()):
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "server.log"), "w") as f:
        f.write("[Harness] live at sync tick 60\n" + "".join(lines))
    scen = {"duration_ticks": 1000, "actions": [{"action": a} for a in actions]}
    return peer_drop.run({"run_dir": d, "scenario": scen, "thresholds": {}})["verdict"]


def main():
    drop = "[Harness] peer_disconnected id=7 at sync tick %d\n"
    assert _v([]) == base.PASS
    assert _v([drop % 1040]) == base.PASS, "left at its deadline"
    assert _v([drop % 600]) == base.FAIL, "timed out mid-match"
    assert _v([drop % 600], actions=["pause_quit"]) == base.SKIP
    print("test_peer_drop: ok")


if __name__ == "__main__":
    main()
