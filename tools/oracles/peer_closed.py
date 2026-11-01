"""peer_closed oracle (T144, B-g; T153 server loss + rejoin): after a peer leaves the match through a
harness lifecycle action (pause_quit = the real pause-menu quit; quit_to_hangar = its pre-T145 name), its
multiplayer peer must be closed. Harness prints `[Harness] peer_check <slot>:
connected=<bool>` 60 ticks after the action. B-g: quitting just changed scene,
the client stayed connected, and the server kept streaming RPCs into an Arena
the client no longer had (log flood).
"""
import glob
import os
import re

from . import base

NAME = "peer_closed"


def run(ctx):
    logs = sorted(glob.glob(os.path.join(ctx.get("run_dir") or "", "*.log")))
    quits, bad = 0, []
    for path in logs:
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        if not re.search(r"\[Harness\] action (pause_quit|quit_to_hangar)", text):
            continue
        quits += 1
        m = re.search(r"\[Harness\] peer_check \S+: connected=(\w+)", text)
        if m is None:
            bad.append("%s: no peer_check after quit (process ended too soon?)" % role)
        elif m.group(1) != "false":
            bad.append("%s: still connected 60 ticks after quitting" % role)
    # T153 (V40 exception): server gone -> peer torn down, back at the title
    for path in logs:
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        for m in re.finditer(r"\[Harness\] server_lost_check \S*: connected=(\w+) scene=(\S+) rejoin=(\w+)", text):
            quits += 1
            if m.group(1) != "false" or m.group(2) != "TitleScreen":
                bad.append("%s: %s 90 frames after losing the server (connected=%s), not the title"
                           % (role, m.group(2), m.group(1)))
        if "[Harness] action rejoin" in text and "rejoin=true" not in text:
            bad.append("%s: mid-match rejoin was not refused (never kicked back to the title)" % role)
    # T167: host SIGKILLed -> every client must notice (peer timeout) and print its server_lost_check
    srv = os.path.join(ctx.get("run_dir") or "", "server.log")
    if os.path.exists(srv) and "[Harness] action kill_client" in open(srv, errors="replace").read():
        for path in logs:
            if os.path.basename(path).startswith("client") and "server_lost_check" not in open(path, errors="replace").read():
                quits += 1
                bad.append("%s never noticed the host died" % os.path.basename(path)[: -len(".log")])
    if not quits:
        return base.verdict(NAME, base.SKIP, note="no lifecycle quit in run")
    if bad:
        return base.verdict(NAME, base.FAIL, note="; ".join(bad))
    return base.verdict(NAME, base.PASS, note="%d quitting peer(s) disconnected" % quits)
