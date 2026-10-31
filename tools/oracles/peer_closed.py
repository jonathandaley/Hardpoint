"""peer_closed oracle (T144, B-g): after a peer leaves the match through a
harness lifecycle action (e.g. quit_to_hangar = the real pause-menu quit), its
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
        if not re.search(r"\[Harness\] action (quit_to_hangar)", text):
            continue
        quits += 1
        m = re.search(r"\[Harness\] peer_check \S+: connected=(\w+)", text)
        if m is None:
            bad.append("%s: no peer_check after quit (process ended too soon?)" % role)
        elif m.group(1) != "false":
            bad.append("%s: still connected 60 ticks after quitting to hangar" % role)
    if not quits:
        return base.verdict(NAME, base.SKIP, note="no lifecycle quit in run")
    if bad:
        return base.verdict(NAME, base.FAIL, note="; ".join(bad))
    return base.verdict(NAME, base.PASS, note="%d quitting peer(s) disconnected" % quits)
