#!/usr/bin/env python3
"""T290: the security run. Starts a real dedicated server on loopback and attacks it
from outside with three hostile clients, then checks the server came through:

  account_attack.py   the account endpoint (TLS JSON lines)
  attacker.tscn       a modified game client (forged RPCs) + an honest "victim" player
  raw_attack.gd       a peer that speaks ENet but not the game (handshake abuse, fuzz)

Every check prints `[sec] <name>: OK | VULN <why>`; exit code = number of VULN lines
(0 = green). Everything targets 127.0.0.1 on a scratch userdata dir.

    run_security.py [--port 28900] [--out DIR] [--godot PATH] [--skip account,client,raw]
"""
import argparse
import os
import re
import shutil
import socket
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def wait_port(port, secs):
    t0 = time.time()
    while time.time() - t0 < secs:
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1.0).close()
            return True
        except OSError:
            time.sleep(0.3)
    return False


def wait_line(path, needle, secs):
    t0 = time.time()
    while time.time() - t0 < secs:
        try:
            if needle in open(path, errors="replace").read():
                return True
        except OSError:
            pass
        time.sleep(0.5)
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=28900)
    ap.add_argument("--out", default=None)
    ap.add_argument("--godot", default=os.environ.get("GODOT", os.path.expanduser("~/bin/godot")))
    ap.add_argument("--skip", default="")
    args = ap.parse_args()
    skip = set(filter(None, args.skip.split(",")))
    out = os.path.abspath(args.out or os.path.join(ROOT, "build", "security_runs", time.strftime("%Y%m%d_%H%M%S")))
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    lines = []
    procs = []

    def say(name, why=""):
        line = "[sec] %s: %s" % (name, "VULN " + why if why else "OK")
        print(line, flush=True)
        lines.append(line)

    def collect(text):
        for ln in text.splitlines():
            if ln.startswith("[sec] ") and not ln.startswith("[sec] done"):
                print(ln, flush=True)
                lines.append(ln)

    def spawn(name, cmd, cwd=ROOT):
        env = dict(os.environ, XDG_DATA_HOME=os.path.join(out, name + "_data"))
        f = open(os.path.join(out, name + ".log"), "w")
        p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, env=env, cwd=cwd)
        procs.append(p)
        return p

    slog = os.path.join(out, "server.log")
    try:
        server = spawn("server", [args.godot, "--headless", "--path", ROOT, "--",
                                  "--server=%d" % args.port, "--team-size=2", "--min-players=2"])
        if not wait_port(args.port + 1, 30):
            say("server_start", "the dedicated server did not open its account port")
            return 1

        victim_id = 0
        if "client" not in skip:
            spawn("victim", [args.godot, "--headless", "--path", ROOT, "res://tools/security/attacker.tscn", "--",
                             "--sec-port=%d" % args.port, "--sec-mode=victim", "--sec-secs=150"])
            vlog = os.path.join(out, "victim.log")
            if not wait_line(vlog, "scene=Lobby", 40):
                say("victim_join", "the honest client never reached the lobby")
            m = re.search(r"\[victim\] id=(\d+)", open(vlog, errors="replace").read())
            victim_id = int(m.group(1)) if m else 0
            spawn("attacker", [args.godot, "--headless", "--path", ROOT, "res://tools/security/attacker.tscn", "--",
                               "--sec-port=%d" % args.port, "--sec-mode=attacker", "--sec-secs=60"])
            alog = os.path.join(out, "attacker.log")
            if not wait_line(alog, "[sec] done", 120):
                say("attacker_run", "the attacking client did not finish (see attacker.log)")
            collect(open(alog, errors="replace").read())

        if "raw" not in skip:
            raw_dir = os.path.join(out, "raw")  # outside the project: no game code loads
            os.makedirs(raw_dir)
            shutil.copy(os.path.join(HERE, "raw_attack.gd"), raw_dir)
            ver = "--sec-ver=" + re.search(r"^const NET_VERSION := (\d+)", open(os.path.join(ROOT, "autoloads", "Game.gd")).read(), re.M).group(1)
            try:
                r = subprocess.run([args.godot, "--headless", "-s", os.path.join(raw_dir, "raw_attack.gd"), "--",
                                    "--sec-port=%d" % args.port, "--sec-victim=%d" % victim_id, ver],
                                   capture_output=True, text=True, timeout=240, cwd=raw_dir)
                collect(r.stdout)
                if "[sec] done" not in r.stdout:
                    say("raw_run", "the raw attacker did not finish: %s" % r.stdout[-300:])
            except subprocess.TimeoutExpired:
                say("raw_run", "the raw attacker timed out")
            # half-open flood: while it holds its connections, an honest stranger must get in
            flood = subprocess.Popen([sys.executable, os.path.join(HERE, "udp_attack.py"), str(args.port), "200", "10"],
                                     stdout=subprocess.PIPE, text=True)
            time.sleep(4.0)
            r = subprocess.run([args.godot, "--headless", "-s", os.path.join(raw_dir, "raw_attack.gd"), "--",
                                "--sec-port=%d" % args.port, "--sec-join-only=halfopen_flood", ver],
                               capture_output=True, text=True, timeout=60, cwd=raw_dir)
            collect(r.stdout)
            collect(flood.communicate(timeout=30)[0])

        # last: its floods use up this address's request / sign-up budget (the victim signed up above)
        if "account" not in skip:
            r = subprocess.run([sys.executable, os.path.join(HERE, "account_attack.py"), str(args.port + 1)],
                               capture_output=True, text=True, timeout=600)
            collect(r.stdout)

        # ---- did the server (and the honest player) come through? ----
        time.sleep(3.0)
        say("server_alive", "" if server.poll() is None else "the server process died (exit %s)" % server.returncode)
        sys.path.insert(0, HERE)
        # T400: a player who never readies up must not hold the lobby hostage. A second server
        # (30 s wait, the shortest allowed), one honest ready player, one idler: the match starts
        # without the idler, who watches it.
        if "client" not in skip:
            hp = args.port + 10
            spawn("server2", [args.godot, "--headless", "--path", ROOT, "--", "--server=%d" % hp,
                              "--team-size=2", "--min-players=1", "--lobby-idle=30"])
            if wait_port(hp + 1, 30):
                for mode in ("idler", "victim"):
                    spawn(mode + "2", [args.godot, "--headless", "--path", ROOT, "res://tools/security/attacker.tscn", "--",
                                       "--sec-port=%d" % hp, "--sec-mode=%s" % mode, "--sec-secs=75"])
                    time.sleep(3.0)
                wait_line(os.path.join(out, "idler2.log"), "[idler] done", 110)
                wait_line(os.path.join(out, "victim2.log"), "[victim] done", 30)
            idl = open(os.path.join(out, "idler2.log"), errors="replace").read() if os.path.exists(os.path.join(out, "idler2.log")) else ""
            vic = open(os.path.join(out, "victim2.log"), errors="replace").read() if os.path.exists(os.path.join(out, "victim2.log")) else ""
            s2 = open(os.path.join(out, "server2.log"), errors="replace").read()
            early = [ln for ln in vic.splitlines() if ln.startswith("[victim] t=") and int(re.search(r"t=(\d+)", ln).group(1)) <= 20]
            why = ""
            if not any("scene=Arena" in ln for ln in vic.splitlines()):
                why = "one player who never readied up kept the match from starting (75 s)"
            elif any("scene=Arena" in ln for ln in early):
                why = "the match started without an unready player after under 20 s (the wait is 30 s here)"
            elif "scene=Arena own_mechs=0 watching=true" not in idl:
                why = "the idle player is not watching the match it sat out: %s" % (idl.strip().splitlines() or ["(no log)"])[-2]
            elif "SCRIPT ERROR" in idl + vic + s2:
                why = "script errors when a match starts without an idle player"
            say("lobby_hostage", why)

        import account_attack
        ok, dt = account_attack.alive(args.port + 1)
        say("accounts_alive", "" if ok else "the account endpoint no longer answers (%.1f s)" % dt)
        if "client" not in skip:
            tail = [ln for ln in open(os.path.join(out, "victim.log"), errors="replace").read().splitlines()
                    if ln.startswith("[victim] t=")]
            last = tail[-1] if tail else ""
            why = ""
            if "connected=true" not in last:
                why = "the honest player lost its connection: %s" % last
            elif "nonfinite_mechs=0" not in last:
                why = "the honest player sees mechs at non-finite positions: %s" % last
            # (not "its mech is alive": bots shoot it down in ordinary play once the run is long
            # enough -- a forged kill is attacker.gd's forged_damage check)
            say("victim_ok", why)
        # The ENGINE refusing junk logs an ERROR line each time (its parser, RPC mode and
        # argument checks): expected, counted for information. GAME code must never fault on
        # hostile input: a SCRIPT ERROR line means a handler read a client's value unchecked.
        text = open(slog, errors="replace").read()
        errs = [ln for ln in text.splitlines() if "SCRIPT ERROR" in ln or "FATAL" in ln]
        kinds = sorted(set(re.sub(r"\d+", "N", e)[:160] for e in errs))
        say("server_script_errors", "" if not errs else "hostile input made game code fault %d times, e.g. %s" % (
            len(errs), " || ".join(kinds[:4])))
        engine = sum(1 for ln in text.splitlines() if ln.startswith("ERROR:"))
        print("[sec] info: server log %d KB, %d engine refusal lines, %d [sec-refused] lines" % (
            len(text) // 1024, engine, text.count("[sec-refused]")), flush=True)
    finally:
        for p in procs:
            if p.poll() is None:
                p.terminate()
        for p in procs:
            try:
                p.wait(timeout=10)
            except subprocess.TimeoutExpired:
                p.kill()
    vulns = [ln for ln in lines if ": VULN " in ln]
    print("=== security run: %d checks, %d VULN -> %s (logs: %s) ===" % (
        len(lines), len(vulns), "FAIL" if vulns else "PASS", out), flush=True)
    return len(vulns)


if __name__ == "__main__":
    sys.exit(main())
