#!/usr/bin/env python3
"""T290: half-open connection flood on the game port (ENet over UDP).

ENet gives a connection a slot on its FIRST packet, before the sender has answered
anything. This sends `count` connect requests from as many sockets and never completes
them, re-sending for `hold` seconds so the slots stay taken; run_security.py checks that an
honest player can still join meanwhile. Loopback only (HOST is fixed).

    udp_attack.py <game_port> [count=200] [hold=10]
"""
import os
import socket
import struct
import sys
import time

HOST = "127.0.0.1"


def connect_packet():
    # protocol header: peer id 0xFFF (none yet) + "sent time" flag; then a CONNECT command
    head = struct.pack("!HH", 0x8FFF, 0)
    cmd = struct.pack("!BBH", 0x82, 0xFF, 1)  # CONNECT | ack flag, channel 0xFF, reliable seq 1
    body = struct.pack("!HBBIIIIIIIIII", 0, 0xFF, 0xFF, 1392, 32768, 3, 0, 0, 5000, 2, 2,
                       struct.unpack("!I", os.urandom(4))[0], struct.unpack("!I", os.urandom(4))[0] | 2)
    return head + cmd + body


def main():
    port = int(sys.argv[1])
    count = int(sys.argv[2]) if len(sys.argv) > 2 else 200
    hold = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
    socks = []
    for _ in range(count):
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.setblocking(False)
        socks.append((s, connect_packet()))
    t0 = time.time()
    answered = 0
    while time.time() - t0 < hold:
        for s, pkt in socks:
            try:
                s.sendto(pkt, (HOST, port))
            except OSError:
                pass
        time.sleep(1.0)
        for s, _ in socks:
            try:
                while s.recv(2048):
                    answered += 1
            except OSError:
                pass
    print("[sec] info: %d half-open connections held for %.0f s (%d server replies ignored)" % (count, hold, answered), flush=True)


if __name__ == "__main__":
    main()
