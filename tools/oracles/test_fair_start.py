"""Self-check for fair_start.live_tick (T163: per-match live tick).
Run: python3 -m tools.oracles.test_fair_start
"""
import os
import tempfile

from . import fair_start


def main():
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "server.log"), "w") as f:
        f.write("x\n[Harness] live at sync tick 67\ny\n[Harness] live at sync tick 41\n")
    os.makedirs(os.path.join(d, "match2"))
    os.makedirs(os.path.join(d, "match3"))
    assert fair_start.live_tick(d) == 67
    assert fair_start.live_tick(os.path.join(d, "match2")) == 41
    assert fair_start.live_tick(os.path.join(d, "match3") + "/") is None, "match 3 never went live"
    assert fair_start.live_tick(os.path.join(d, "nope")) is None
    print("test_fair_start: ok")


if __name__ == "__main__":
    main()
