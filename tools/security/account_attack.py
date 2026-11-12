#!/usr/bin/env python3
"""T290: hostile client for the account endpoint (scripts/AccountServer.gd).

Loopback only (HOST is fixed): it attacks a dedicated server started on this machine
by tools/security/run_security.py. Each check prints `[sec] <name>: OK|VULN <detail>`
and the exit code is the number of VULN lines.

    account_attack.py <account_port> [--only name,name]
"""
import json
import socket
import ssl
import sys
import time

HOST = "127.0.0.1"  # never anything else: this is an attack tool for the local test server


HONEST = "127.0.0.2"  # an honest client's own address: the attacker's per-address limits don't apply to it


def conn(port, timeout=5.0, src=None):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    raw = socket.create_connection((HOST, port), timeout=timeout, source_address=(src, 0) if src else None)
    return ctx.wrap_socket(raw, server_hostname="hardpoint")


def send_raw(port, data, timeout=5.0, src=None):
    """One connection, raw bytes out, one reply line back ('' = closed without one)."""
    try:
        s = conn(port, timeout, src)
        s.sendall(data)
        buf = b""
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
        s.close()
        return buf.decode("utf-8", "replace").strip()
    except (OSError, ssl.SSLError) as e:
        return "ERR %s" % type(e).__name__


def req(port, d, timeout=5.0, src=None):
    out = send_raw(port, (json.dumps(d) + "\n").encode(), timeout, src)
    try:
        r = json.loads(out, strict=False)
        return r if isinstance(r, dict) else {"_raw": out}
    except ValueError:
        return {"_raw": out}


def alive(port):
    """The endpoint still gives an honest client (its own address) a real answer promptly."""
    t0 = time.time()
    r = req(port, {"op": "login", "email": "nobody%d@example.com" % (int(t0 * 1000) % 100000),
                   "password": "x" * 10}, timeout=4.0, src=HONEST)
    return r.get("error") == "wrong email or password", time.time() - t0


CHECKS = []


def check(fn):
    CHECKS.append(fn)
    return fn


@check
def wrong_types(port):
    """Non-string fields must get a clean refusal, and must not wedge the endpoint."""
    bad = [{"op": 5}, {"op": ["signup"]}, {"op": "login", "email": 5, "password": 7},
           {"op": "login", "email": {"a": 1}, "password": ["x"]}, {"op": "signup", "email": "t1@example.com",
           "password": 12345678, "callsign": {"x": 1}}, {"op": "unlock_skill", "session": 5, "key": 9},
           {"op": "upgrade_skill", "session": None, "key": None}, [], "str", 5, None,
           {"op": None, "email": None, "password": None}]
    for b in bad:
        r = req(port, b)
        if r.get("ok") is not False:
            return "request %r got %r (wanted a clean refusal)" % (b, r)
    ok, dt = alive(port)
    if not ok:
        return "endpoint stopped answering after malformed requests (%.1f s)" % dt


@check
def garbage_bytes(port):
    for blob in [b"\x00" * 100 + b"\n", b"\xff\xfe\xfd\n", b"{" * 3000 + b"\n", b"[" * 4000 + b"\n",
                 b'{"op":"login","email":"' + b"a" * 5000 + b'"}\n', b"\n", b"\n\n\n",
                 b'{"op":"login"}\n{"op":"login"}\n']:
        send_raw(port, blob, timeout=3.0)
    ok, dt = alive(port)
    if not ok:
        return "endpoint stopped answering after garbage (%.1f s)" % dt


@check
def email_injection(port):
    """Emails become ConfigFile section names and log lines: no control chars / brackets."""
    pw = "correct-horse-battery"
    for e in ["a@b.c]\n[admin@x.y", "x\n[evil]\nk=1\n@b.co", "a\tb@c.de", "a@b.c\r\nFAKE LOG LINE", 'a"@b.cd',
              "a[b@c.de", "a]b@c.de", "a\\b@c.de", "a;b@c.de", "a=b@c.de", "a\x00b@c.de"]:
        r = req(port, {"op": "signup", "email": e, "password": pw, "callsign": "X"})
        if r.get("ok"):
            return "signup accepted the email %r" % e


@check
def callsign_sanitized(port):
    pw = "correct-horse-battery"
    r = req(port, {"op": "signup", "email": "cs%d@example.com" % int(time.time() * 1000), "password": pw,
                   "callsign": "[b]A\nB\x07[/b]" + "Z" * 100})
    name = (r.get("profile") or {}).get("pilot_name", "")
    if not r.get("ok"):
        return None  # refused outright: fine
    if len(name) > 16 or any(ord(ch) < 32 for ch in name) or "[" in name:
        return "callsign stored as %r (control chars / markup / too long)" % name


@check
def oversized(port):
    r = send_raw(port, b"A" * (1 << 20), timeout=5.0)  # 1 MiB, no newline
    ok, dt = alive(port)
    if not ok:
        return "endpoint stopped answering after a 1 MiB line (%.1f s)" % dt


@check
def lockout_holds(port):
    """Password guessing: after the lock, even the right password is refused for a while,
    and a burst of parallel guesses can't slip past the counter."""
    pw = "correct-horse-battery"
    email = "lock%d@example.com" % int(time.time() * 1000)
    if not req(port, {"op": "signup", "email": email, "password": pw, "callsign": "L"}).get("ok"):
        return "could not sign up the test account"
    tried = 0
    for i in range(12):
        r = req(port, {"op": "login", "email": email, "password": "guess-%04d" % i})
        if r.get("error") == "wrong email or password":
            tried += 1
    if tried > 6:
        return "%d password guesses were evaluated in a row with no lock" % tried
    if req(port, {"op": "login", "email": email, "password": pw}).get("ok"):
        return "the right password still worked straight after the guesses (no lock)"


@check
def signup_flood(port):
    """One address must not be able to mint accounts without limit (disk + CPU)."""
    pw = "correct-horse-battery"
    made = 0
    stamp = int(time.time() * 1000)
    for i in range(40):
        if req(port, {"op": "signup", "email": "f%d_%d@example.com" % (stamp, i), "password": pw,
                      "callsign": "F"}).get("ok"):
            made += 1
    if made >= 40:
        return "40 of 40 sign-ups from one address accepted back to back"


@check
def connection_flood(port):
    """Idle connections must not starve real requests (bounded: 300 sockets, loopback)."""
    socks = []
    try:
        for _ in range(300):
            try:
                s = socket.create_connection((HOST, port), timeout=2.0)
                socks.append(s)  # TCP only, never speaks TLS
            except OSError:
                break
        time.sleep(1.0)
        ok, dt = alive(port)
        if not ok:
            return "with %d idle connections open a real request got no answer (%.1f s)" % (len(socks), dt)
        if dt > 3.0:
            return "with %d idle connections open a real request took %.1f s" % (len(socks), dt)
    finally:
        for s in socks:
            s.close()


@check
def hash_flood(port):
    """A burst of logins (each costs a password hash) must not stall the endpoint for long."""
    import threading
    def one():
        req(port, {"op": "login", "email": "hf@example.com", "password": "p" * 128}, timeout=20.0)
    th = [threading.Thread(target=one) for _ in range(120)]
    for t in th:
        t.start()
    time.sleep(0.5)
    ok, dt = alive(port)
    for t in th:
        t.join()
    if not ok or dt > 3.5:
        return "during a 120-login burst a real request took %.1f s (answered=%s)" % (dt, ok)


@check
def session_guess(port):
    for s in ["", "0" * 64, "f" * 64, "../../etc/passwd", "a" * 100000]:
        r = req(port, {"op": "unlock_skill", "session": s, "key": "repair_rate"})
        if r.get("ok"):
            return "skill op accepted the session %r" % s[:20]


def main():
    port = int(sys.argv[1])
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1].split(",")
    vulns = 0
    for fn in CHECKS:
        if only and fn.__name__ not in only:
            continue
        try:
            why = fn(port)
        except Exception as e:  # a check that cannot run is a failure, not a pass
            why = "check crashed: %r" % e
        print("[sec] %s: %s" % (fn.__name__, "VULN " + why if why else "OK"), flush=True)
        vulns += 1 if why else 0
    return vulns


if __name__ == "__main__":
    sys.exit(main())
