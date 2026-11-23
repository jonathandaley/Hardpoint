#!/usr/bin/env python3
"""T422: raw attacks on the game port, now WebSocket over TCP (replaces raw_attack.gd + udp_attack.py,
which spoke ENet). A peer that speaks WebSocket but not the game, or not even WebSocket. Stdlib only,
loopback only (HOST is fixed). Lines: `[sec] <name>: OK | VULN <why>`.

    ws_attack.py <game_port> <net_version> [--victim=<peer id>] [--join-only=<check>]

Godot's WebSocketMultiplayerPeer: after the WebSocket handshake the server's first message is the
client's peer id (4 bytes, little endian); then every binary message is one SceneMultiplayer packet:
byte 0 = command (7 = SYS), SYS byte 1 = 0 AUTH / 3 RELAY; an AUTH packet with no payload = "I have
completed auth".
"""
import base64
import os
import random
import socket
import struct
import sys
import time

HOST = "127.0.0.1"
SYS = 7
OP_CONT, OP_TEXT, OP_BIN, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 8, 9, 10
rng = random.Random(422 + int(time.time()) % 1000)


def say(check, why=""):
    print("[sec] %s: %s" % (check, "OK" if not why else "VULN " + why), flush=True)


class WS:
    """A minimal, deliberately unforgiving WebSocket client (it sends whatever it is told to)."""

    def __init__(self, port, src="127.0.0.1", timeout=3.0, handshake=True):
        self.s = socket.create_connection((HOST, port), timeout=timeout, source_address=(src, 0))
        self.s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.buf = b""
        self.closed = False
        self.id = 0
        if handshake:
            self.handshake(port)

    def handshake(self, port):
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall(("GET / HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (HOST, port, key)).encode())
        while b"\r\n\r\n" not in self.buf:
            d = self.s.recv(4096)
            if not d:
                raise ConnectionError("closed during the handshake")
            self.buf += d
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        if b" 101 " not in head.split(b"\r\n")[0]:
            raise ConnectionError("handshake refused: %r" % head[:80])

    def frame(self, payload, op=OP_BIN, fin=True, mask=True):
        n = len(payload)
        b0 = (0x80 if fin else 0) | op
        if n < 126:
            hdr = struct.pack("!BB", b0, (0x80 if mask else 0) | n)
        elif n < 65536:
            hdr = struct.pack("!BBH", b0, (0x80 if mask else 0) | 126, n)
        else:
            hdr = struct.pack("!BBQ", b0, (0x80 if mask else 0) | 127, n)
        if not mask:
            return hdr + payload
        k = os.urandom(4)
        return hdr + k + bytes(c ^ k[i % 4] for i, c in enumerate(payload))

    def send(self, payload, **kw):
        try:
            self.s.sendall(self.frame(bytes(payload), **kw))
        except OSError:
            self.closed = True

    def raw(self, data):
        try:
            self.s.sendall(data)
        except OSError:
            self.closed = True

    def pump(self, secs):
        """Read for `secs` -> list of binary/text message payloads (sets .closed on EOF / close frame)."""
        out = []
        end = time.time() + secs
        first = True
        while time.time() < end and not self.closed:
            if not first:  # the first pass parses what came with the handshake reply
                self.s.settimeout(max(0.01, end - time.time()))
                try:
                    d = self.s.recv(65536)
                except socket.timeout:
                    break
                except OSError:
                    self.closed = True
                    break
                if not d:
                    self.closed = True
                    break
                self.buf += d
            first = False
            while True:
                m = self._take()
                if m is None:
                    break
                op, p = m
                if op == OP_CLOSE:
                    self.closed = True
                elif op == OP_PING:
                    self.send(p, op=OP_PONG)
                elif op in (OP_BIN, OP_TEXT):
                    if self.id == 0 and len(p) == 4:
                        self.id = struct.unpack("<I", p)[0]  # the server's first message: our peer id
                    else:
                        out.append(p)
        return out

    def _take(self):
        b = self.buf
        if len(b) < 2:
            return None
        op, n, i = b[0] & 0x0F, b[1] & 0x7F, 2
        if n == 126:
            if len(b) < 4:
                return None
            n, i = struct.unpack("!H", b[2:4])[0], 4
        elif n == 127:
            if len(b) < 10:
                return None
            n, i = struct.unpack("!Q", b[2:10])[0], 10
        if len(b) < i + n:
            return None
        self.buf = b[i + n:]
        return op, b[i:i + n]

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass
        self.closed = True


def auth(text):
    return bytes([SYS, 0]) + text.encode("utf-8", "surrogatepass")


def hello(token, ver):
    return auth("token:%s||%d" % (token, ver))


def welcomed(pkts):
    return any(p[2:] == b"ok" or len(p) > 100 for p in pkts)


def connect(port, src="127.0.0.1", wait=3.0):
    """A WebSocket peer that has its id, or None (refused / timed out)."""
    try:
        c = WS(port, src)
    except (OSError, ConnectionError):
        return None
    c.pump(min(wait, 1.0))
    return c if c.id and not c.closed else None


def honest_join(port, ver):
    """An honest stranger from its own address (127.0.0.2: the attacker's per-address limits don't apply)."""
    c = connect(port, "127.0.0.2")
    if c is None:
        return False
    c.send(hello("honest%d" % rng.randint(0, 99999), ver))
    ok = welcomed(c.pump(3.0))
    c.close()
    return ok


def run(port, ver, victim):
    # 0. sanity: a plain hello gets an answer (else every check below is meaningless)
    c = connect(port)
    if c is None:
        say("raw_connect", "could not open a WebSocket connection to %s:%d (is the server up?)" % (HOST, port))
        return 1
    c.send(hello("rawpeer0", ver))
    first = c.pump(1.5)
    one = sum(len(p) for p in first)
    print("[sec] info: first hello answered with %d bytes in %d packets (peer id %d)" % (one, len(first), c.id), flush=True)
    say("honest_hello", "" if welcomed(first) else "a current-version hello was not welcomed (stale version?)")

    # 0b. T388: a hello with no / another / a junk version is told why and never admitted
    for h in ["token:old", "token:old||0", "token:old||%d" % (ver + 1), "token:old||-1", "token:old||%dx" % ver,
              "token:old||%d|%d" % (ver + 1, ver), "token:old|%d" % ver, "token:old||" + "9" * 40]:
        v = connect(port)
        if v is None:
            continue
        v.send(auth(h))
        ans = v.pump(1.2)
        told = any(b"Update the game" in p or b"older version" in p for p in ans)
        v.send(bytes([SYS, 0]))  # "auth complete" anyway
        v.pump(2.6)
        say("version_gate(%s)" % h[9:21], "" if told and not welcomed(ans) and v.closed
            else "hello '%s': told=%s welcomed=%s dropped=%s" % (h[:30], told, welcomed(ans), v.closed))
        v.close()

    # 1. repeated hellos: each one must not cost the server another full answer
    for _ in range(300):
        c.send(hello("rawpeer0", ver))
    spam = c.pump(2.5)
    got = sum(len(p) for p in spam)
    say("hello_spam", "" if got <= max(one, 64) * 3 or c.closed
        else "300 repeated hellos were answered with %d bytes: each costs a fresh reply before any login" % got)
    c.close()

    # 2. oversized / odd hellos, and frames no client should send
    c = connect(port)
    if c is not None:
        c.send(auth("token:" + "A" * 200000))
        c.send(auth("token:|||||\n[Server] fake log line\n"))
        c.send(auth("\u0000\u0001token:"))
        for t in ("ready", "go", "ok"):
            c.send(auth(t))
        c.pump(0.8)
        c.close()
    c = connect(port)
    if c is not None:
        c.send(hello("unmasked", ver), mask=False)  # RFC 6455: a server must fail this connection
        c.pump(1.5)
        say("unmasked_frame", "" if c.closed else "a client frame without a mask was accepted")
        c.close()
    c = connect(port)
    if c is not None:
        c.raw(struct.pack("!BBQ", 0x82, 0xFF, 1 << 40))  # announces a 1 TiB message, sends none of it
        c.pump(1.5)
        c.close()
    c = connect(port)
    if c is not None:
        for _ in range(200):  # a message that never ends: continuation frames forever
            c.send(b"A" * 1000, op=OP_CONT, fin=False)
        c.pump(1.0)
        c.close()

    # 3. a peer that never says hello, sending non-auth packets
    c = connect(port)
    dropped = False
    if c is not None:
        for _ in range(400):
            c.send(bytes([rng.randint(0, 6)]) + os.urandom(rng.randint(0, 40)))
        c.pump(7.0)
        dropped = c.closed
        c.close()
    say("preauth_noise", "" if dropped else "a peer that never said hello was still connected after 7 s")

    # 4. silent connections hogging the join slots (one address)
    hogs = [h for h in (connect(port, wait=0.6) for _ in range(40)) if h is not None]
    say("slot_hog", "" if honest_join(port, ver)
        else "%d silent connections from one address filled the server: a real player could not join" % len(hogs))
    for h in hogs:
        h.close()

    # 5. become a real (spectating / lobby) peer by hand, then fuzz the packet parser
    c = connect(port)
    if c is not None:
        c.send(hello("fuzzer", ver))
        if not any(p[2:] == b"ok" for p in c.pump(1.5)):
            c.send(auth("ready"))
            c.pump(1.5)
        c.send(bytes([SYS, 0]))  # "auth complete"
        c.pump(1.5)
        sent = 0
        for rnd in range(3000):
            n = 60000 if rnd % 50 == 0 else rng.randint(0, 96)
            c.send(bytes([(rnd % 8) | (rng.randint(0, 31) << 3)]) + os.urandom(n))
            sent += 1
            if rnd % 200 == 0:
                c.pump(0.03)
                if c.closed:
                    break
        if victim > 0:  # a relay to the victim carrying junk
            r = bytes([SYS, 3]) + struct.pack("<i", victim) + bytes([0] + [255] * 8)
            for _ in range(200):
                c.send(r)
        c.send(bytes([1, 255, 255, 255, 127]) + b"A" * (1 << 20))  # a path with 1 MiB of text
        c.pump(2.0)
        print("[sec] info: fuzz sent %d packets as an admitted peer" % sent, flush=True)
        c.close()
    return 0


def flood(port, ver, count=200, hold=10.0):
    """Half-open connections: TCP connections that never finish (or never start) the WebSocket
    handshake, and some that drip it a byte at a time; an honest stranger must still get in."""
    socks = []
    for i in range(count):
        try:
            s = socket.create_connection((HOST, port), timeout=2.0)
            if i % 2:
                s.sendall(b"GET / HTTP/1.1\r\nHost: x\r\n")  # a handshake that never ends
            socks.append(s)
        except OSError:
            pass
    time.sleep(min(hold, 3.0))
    ok = honest_join(port, ver)
    say("halfopen_flood", "" if ok else "%d half-open connections kept an honest player out" % len(socks))
    end = time.time() + max(0.0, hold - 3.0)
    while time.time() < end:  # drip, slowloris style
        for s in socks[::2]:
            try:
                s.sendall(b"X")
            except OSError:
                pass
        time.sleep(0.5)
    for s in socks:
        s.close()


def main():
    port, ver = int(sys.argv[1]), int(sys.argv[2])
    opts = dict(a[2:].split("=", 1) for a in sys.argv[3:] if a.startswith("--") and "=" in a)
    if "join-only" in opts:
        say(opts["join-only"], "" if honest_join(port, ver) else "an honest player (another address) could not join")
    elif "flood" in opts:
        flood(port, ver)
    else:
        rc = run(port, ver, int(opts.get("victim", 0)))
        if rc:
            return rc
    print("[sec] done", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
