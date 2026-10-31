"""Red/green self-check for crash_scan + log_flood (T143), using synthetic logs
and, when present, the archived T158_fix_bad run (real RPC-before-Arena errors).
Run: python3 -m tools.oracles.test_crash_scan
"""
import os
import tempfile

from . import base, crash_scan, log_flood

TEARDOWN_NOISE = ("ERROR: 3 resources still in use at exit (run with --verbose for details).\n"
                  "   at: clear (core/io/resource.cpp:123)\n"
                  "ERROR: Unable to send packet on channel 0, max channels: 3\n")


def _run(log_text):
    d = tempfile.mkdtemp()
    with open(os.path.join(d, "client_1.log"), "w") as f:
        f.write(log_text)
    ctx = {"run_dir": d, "thresholds": {}}
    return crash_scan.run(ctx)["verdict"], log_flood.run(ctx)["verdict"]


def main():
    assert _run("[Harness] ok\n" + TEARDOWN_NOISE) == (base.PASS, base.PASS), "teardown noise is allowed"
    b_h = 'ERROR: Condition "!is_inside_tree()" is true. Returning: Transform3D()\n   at: get_global_transform\n'
    assert _run(b_h)[0] == base.FAIL, "B-h engine error must fail"
    assert _run('ERROR: boom\n   at: push_error (core/variant/variant_utility.cpp:1)\n')[0] == base.FAIL, "push_error (B37)"
    assert _run("SCRIPT ERROR: Invalid call.\n")[0] == base.FAIL
    b_g = ('ERROR: Node not found: "Arena" (relative to "/root").\n'
           "ERROR: Failed to get cached node from peer 1 with cache ID 5.\n") * 30
    assert _run(b_g) == (base.FAIL, base.FAIL), "B-g flood must fail both"
    allowed_flood = "ERROR: Unable to send packet on channel 0, max channels: 3\n" * 25
    assert _run(allowed_flood) == (base.PASS, base.FAIL), "allowed line, but flooding"
    assert _run("WARNING: rate limit exceeded for peer 7\n" * 25)[1] == base.FAIL, "warning flood"
    real = os.path.join(os.path.dirname(__file__), "..", "..", "build", "suite_runs", "T158_fix_bad")
    if os.path.isdir(real):
        v = crash_scan.run({"run_dir": real, "thresholds": {}})
        assert v["verdict"] == base.FAIL and "Node not found" in v["note"], ("real RPC-before-Arena run", v)
    print("test_crash_scan: ok")


if __name__ == "__main__":
    main()
