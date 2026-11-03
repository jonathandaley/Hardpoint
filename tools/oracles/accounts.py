"""accounts oracle (T207): a signed-in player's match result is applied on the server
(the account store), sent back to that player, and never written to its local profile.

Per client log with `[Harness] account signed in: <email>`: the server log must show
`[Server] account <email>: elo A -> B`, the client's profile must equal
B (`account_profile elo=`, what the server sent back), and its `local_profile elo=`
must be `none` (nothing saved).
"""
import glob
import os
import re

from . import base

NAME = "accounts"


def run(ctx):
    run_dir = ctx.get("run_dir") or ""
    try:
        server = open(os.path.join(run_dir, "server.log"), errors="replace").read()
    except OSError:
        return base.verdict(NAME, base.SKIP, note="no server.log (match 2+ dir)")
    updates = {m.group(1): (int(m.group(2)), int(m.group(3)))
               for m in re.finditer(r"\[Server\] account (\S+): elo (-?\d+) -> (-?\d+)", server)}
    seen = 0
    for path in sorted(glob.glob(os.path.join(run_dir, "client_*.log"))):
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        m = re.search(r"\[Harness\] account signed in: (\S+)", text)
        if m is None:
            continue
        seen += 1
        email = m.group(1)
        if email not in updates:
            return base.verdict(NAME, base.FAIL, peer=role, note="server never applied %s's result" % email)
        after = re.findall(r"\[Harness\] account_profile elo=(-?\d+)", text)
        if not after or int(after[-1]) != updates[email][1]:
            return base.verdict(NAME, base.FAIL, peer=role, note="client elo %s != server's %d"
                                % (after[-1] if after else "?", updates[email][1]))
        local = re.search(r"\[Harness\] local_profile elo=(\S+)", text)
        if local is None or local.group(1) != "none":
            return base.verdict(NAME, base.FAIL, peer=role, note="account result written to the local profile (%s)"
                                % (local.group(1) if local else "no local_profile line"))
    if not seen:
        return base.verdict(NAME, base.SKIP, note="no signed-in client")
    return base.verdict(NAME, base.PASS, note="%d account(s): result applied on the server, sent back, not saved locally"
                        % seen)
