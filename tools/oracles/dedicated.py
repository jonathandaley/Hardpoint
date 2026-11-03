"""dedicated oracle (T204): a dedicated server (`--server`, Game.start_dedicated) ran
the lobby and every match with no player of its own.

FAIL when the server log lacks the dedicated start line, a match did not start from
the server's own lobby countdown (`[Server] match start: N players`) once per
scenario match, any peer saw a mech owned by peer 1 (the server's id: it is never a
player, V35), or a client did not reach every match (`input override done ... match n`).
"""
import glob
import os
import re

from . import base

NAME = "dedicated"


def run(ctx):
    run_dir = ctx.get("run_dir") or ""
    want = int((ctx.get("scenario") or {}).get("matches", 1))
    try:
        server = open(os.path.join(run_dir, "server.log"), errors="replace").read()
    except OSError:  # match 2+ dirs (run_suite '#m2') hold only the jsonl streams
        return base.verdict(NAME, base.SKIP, note="no server.log (match 2+ dir)")
    if "[Server] dedicated on port" not in server:
        return base.verdict(NAME, base.FAIL, peer="server", note="server did not start in dedicated mode")
    starts = re.findall(r"\[Server\] match start: (\d+) players", server)
    if len(starts) < want:
        return base.verdict(NAME, base.FAIL, peer="server",
                            note="%d match start(s) from the lobby countdown, want %d" % (len(starts), want))
    clients = 0
    for path in sorted(glob.glob(os.path.join(run_dir, "client_*.log"))):
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        clients += 1
        if re.search(r"\[Harness\] spawned owner=1 ", text):
            return base.verdict(NAME, base.FAIL, peer=role, note="a mech owned by peer 1 (the server) spawned")
        n = len(re.findall(r"\[Harness\] input override done for client .* match (\d+)\)", text))
        if n < want:
            return base.verdict(NAME, base.FAIL, peer=role, note="reached %d of %d matches" % (n, want))
    if clients == 0:
        return base.verdict(NAME, base.FAIL, note="no client logs")
    return base.verdict(NAME, base.PASS, note="server-run lobby started %d match(es) for %s players, no server mech"
                        % (len(starts), "/".join(starts)))
