"""Red/green self-check for profile_parity (T154). Run: python3 -m tools.oracles.test_profile_parity"""
import os
import tempfile

from . import base, profile_parity


def _v(server_after, client_after, seeds=(1200, 900), saved=None):
    d = tempfile.mkdtemp()
    for role, team, rows, elo0 in (("server", 0, server_after, seeds[0]), ("client_1", 1, client_after, seeds[1])):
        ud = os.path.join(d, role + "_ud")
        os.makedirs(ud)
        with open(os.path.join(d, role + ".log"), "w") as f:
            f.write("[Harness] user_data_dir=%s\n" % ud)
            for n, (elo, xp, coins, winner) in enumerate(rows, 1):
                f.write("[Arena] MP match over. Team %d wins.\n" % winner)
                f.write("[Harness] profile_after match=%d team=%d elo=%d xp=%d coins=%d level=1\n" % (n, team, elo, xp, coins))
        last = (saved or {}).get(role, rows[-1] if rows else None)
        if last:
            with open(os.path.join(ud, "profile.cfg"), "w") as f:
                f.write("[profile]\n\nelo=%d\nxp=%d\ncoins=%d\n" % last[:3])
    scen = {"peers": {"server": {"profile": {"elo": seeds[0]}}, "client_1": {"profile": {"elo": seeds[1]}}}}
    return profile_parity.run({"run_dir": d, "scenario": scen})


def main():
    # 1200 vs 900, underdog client wins: E(server)=0.849 -> -27; client +27; xp: server loss 15*900/1200=11, client 50*1200/900=67
    s1, c1 = profile_parity.expected({"elo": 1200, "xp": 0, "coins": 0}, [900], False), \
        profile_parity.expected({"elo": 900, "xp": 0, "coins": 0}, [1200], True)
    assert (s1["elo"], c1["elo"], s1["xp"], c1["xp"]) == (1173, 927, 11, 67), (s1, c1)
    ok = _v([(1173, 11, 20, 1)], [(927, 67, 75, 1)])
    assert ok["verdict"] == base.PASS, ok
    assert _v([(1173, 11, 20, 1)], [(943, 67, 75, 1)])["verdict"] == base.FAIL, "client used a stale/wrong opponent ELO"
    assert _v([(1173, 11, 20, 1)], [(927, 67, 75, 0)])["verdict"] == base.FAIL, "peers disagree on the winner"
    assert _v([(1173, 11, 20, 1)], [(927, 67, 75, 1)], saved={"client_1": (900, 0, 0)})["verdict"] == base.FAIL, \
        "result not saved"
    # match 2 must start from match 1's results (stale lobby ELO would use the seeds again)
    s2 = profile_parity.expected({"elo": 1173, "xp": 11, "coins": 20}, [927], True)
    c2 = profile_parity.expected({"elo": 927, "xp": 67, "coins": 75}, [1173], False)
    two = _v([(1173, 11, 20, 1), (s2["elo"], s2["xp"], s2["coins"], 0)], [(927, 67, 75, 1), (c2["elo"], c2["xp"], c2["coins"], 0)])
    assert two["verdict"] == base.PASS, two
    stale = profile_parity.expected({"elo": 1173, "xp": 11, "coins": 20}, [900], True)  # server vs the lobby's old 900
    assert stale != s2, "test needs a case where the stale ELO changes the result"
    assert _v([(1173, 11, 20, 1), (stale["elo"], stale["xp"], stale["coins"], 0)],
              [(927, 67, 75, 1), (c2["elo"], c2["xp"], c2["coins"], 0)])["verdict"] == base.FAIL, "stale pre-ELO"
    assert _v([], [])["verdict"] == base.SKIP
    print("test_profile_parity: ok")


if __name__ == "__main__":
    main()
