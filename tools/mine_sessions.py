#!/usr/bin/env python3
"""T556: mine the dedicated server's match recordings for bugs nobody reported.

Usage: mine_sessions.py [root] [--all] [--selftest]

root defaults to /var/lib/hardpoint-sessions (deploy/install.sh makes it readable by the admin).
Every finished match there (a session folder's own files = match 1, matchN/ = later ones; finished =
nothing written for 2 minutes) not mined before (build/mined.json; --all redoes them) gets:
  - the real-session oracles (sync_compare.py tools/sessions/real_session.json): server-only
    checks such as world_invariants and lock_target run, the cross-peer ones SKIP;
  - each F9 mark ("mark" event, Game.mark_moment) with its match time, and a +-20 s cut of the
    recording around it (session_window.py) under build/mined/ to run the oracles / look at;
plus the server journal's ERROR / MARK lines since the last mine, when the journal is readable.
Exit 1 when anything FAILed or there are new marks, 0 when all is quiet.
"""
import glob
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
STATE = os.path.join(REPO, "build", "mined.json")
OUT = os.path.join(REPO, "build", "mined")
QUIET_S = 120
WINDOW_S = 20


def matches(root):
    """[(name, dir)] for every recorded match under root, oldest first."""
    out = []
    for sess in sorted(glob.glob(os.path.join(root, "*"))):
        if os.path.exists(os.path.join(sess, "server.jsonl")):
            out.append((os.path.basename(sess) + "/match1", sess))
        for m in sorted(glob.glob(os.path.join(sess, "match*")), key=lambda p: int(p.rsplit("match", 1)[1] or 0)):
            if os.path.exists(os.path.join(m, "server.jsonl")):
                out.append((os.path.basename(sess) + "/" + os.path.basename(m), m))
    return out


def finished(d, now):
    return all(now - os.path.getmtime(f) > QUIET_S for f in glob.glob(os.path.join(d, "*.jsonl")))


def marks(d):
    """[(tick, peer)] of the F9 marks in a match's server events."""
    out = []
    try:
        with open(os.path.join(d, "server.events.jsonl")) as f:
            for line in f:
                try:
                    e = json.loads(line)
                except ValueError:
                    continue  # torn last line
                if e.get("type") == "mark":
                    out.append((int(e.get("tick", 0)), int(e.get("payload", {}).get("peer", 0))))
    except OSError:
        pass
    return out


def mmss(tick):
    return "%d:%02d" % (tick // 3600, tick // 60 % 60)


def mine(d, name):
    """(report lines, failed?) for one match."""
    lines, bad = [], False
    r = subprocess.run([sys.executable, os.path.join(HERE, "sync_compare.py"),
                        os.path.join(HERE, "sessions", "real_session.json"), d],
                       capture_output=True, text=True)
    for ln in r.stdout.splitlines():
        if "[FAIL]" in ln or (ln.startswith("           {") and bad):
            bad = bad or "[FAIL]" in ln
            lines.append("  " + ln.strip())
    if r.returncode == 2:
        lines.append("  sync_compare error: " + r.stderr.strip()[-300:])
        bad = True
    for tick, peer in marks(d):
        cut = os.path.join(OUT, name.replace("/", "_"), "mark_%d" % tick)
        subprocess.run([sys.executable, os.path.join(HERE, "session_window.py"), d,
                        str(max(0, tick / 60 - WINDOW_S)), str(tick / 60 + WINDOW_S), cut],
                       capture_output=True, text=True)
        lines.append("  MARK by peer %d at %s (tick %d) -> %s" % (peer, mmss(tick), tick, cut))
    return lines, bad


def journal(since):
    try:
        r = subprocess.run(["journalctl", "-u", "hardpoint", "--since", "@%d" % since, "-o", "short-iso",
                            "--no-pager"], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired):
        return ["  (journal not readable)"]
    if r.returncode != 0 or "No journal files" in r.stderr or "can see all messages" in r.stderr:
        return ["  (journal not readable: %s)" % r.stderr.strip()[:120]]
    keep = [ln for ln in r.stdout.splitlines() if "ERROR" in ln or "MARK" in ln]
    return ["  " + ln[:300] for ln in keep[-60:]]


def main(argv):
    if "--selftest" in argv:
        return selftest()
    args = [a for a in argv if not a.startswith("--")]
    root = args[0] if args else "/var/lib/hardpoint-sessions"
    if not os.access(root, os.R_OK | os.X_OK):
        print("%s is not readable (run `sudo deploy/install.sh` once: it grants the admin read access)" % root)
        return 2
    state = {}
    if os.path.exists(STATE) and "--all" not in argv:
        with open(STATE) as f:
            state = json.load(f)
    done, now, alarm = set(state.get("done", [])), time.time(), False
    for name, d in matches(root):
        if name in done or not finished(d, now):
            continue
        lines, bad = mine(d, name)
        alarm = alarm or bad or any("MARK" in ln for ln in lines)
        print("%s: %s" % (name, "FAIL" if bad else "ok") + ("" if not lines else "\n" + "\n".join(lines)))
        done.add(name)
    print("journal since the last mine:")
    print("\n".join(journal(int(state.get("since", now - 86400)))) or "  (no errors or marks)")
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump({"done": sorted(done), "since": int(now)}, f)
    return 1 if alarm else 0


def selftest():
    """A fake finished session with one F9 mark: it is found, reported and cut."""
    import tempfile
    global STATE, OUT
    tmp = tempfile.mkdtemp()
    STATE, OUT = os.path.join(tmp, "mined.json"), os.path.join(tmp, "mined")
    sess = os.path.join(tmp, "root", "2026-11-25_200000")
    os.makedirs(os.path.join(sess, "match2"))
    for d in (sess, os.path.join(sess, "match2")):
        with open(os.path.join(d, "server.jsonl"), "w") as f:
            f.write(json.dumps({"tick": 1, "mech_id": "Mech_0_0"}) + "\n")
        with open(os.path.join(d, "server.events.jsonl"), "w") as f:
            f.write(json.dumps({"tick": 3700, "type": "mark", "mech_id": "", "payload": {"peer": 7}}) + "\n")
        for p in glob.glob(os.path.join(d, "*")):
            os.utime(p, (time.time() - 600, time.time() - 600))
    names = [n for n, _ in matches(os.path.join(tmp, "root"))]
    assert names == ["2026-11-25_200000/match1", "2026-11-25_200000/match2"], names
    assert marks(sess) == [(3700, 7)]
    assert mmss(3700) == "1:01"
    lines, _ = mine(os.path.join(sess, "match2"), names[1])
    assert any("MARK by peer 7 at 1:01" in ln for ln in lines), lines
    assert os.path.exists(os.path.join(OUT, "2026-11-25_200000_match2", "mark_3700", "server.events.jsonl"))
    assert main([os.path.join(tmp, "root")]) == 1
    assert main([os.path.join(tmp, "root")]) == 0  # both mined now: quiet
    print("selftest ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
