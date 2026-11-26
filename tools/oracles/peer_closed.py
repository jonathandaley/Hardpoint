"""peer_closed oracle (T144, B-g; T153 server loss + rejoin): after a peer leaves the match through a
harness lifecycle action (pause_quit = the real pause-menu quit; quit_to_hangar = its pre-T145 name), its
multiplayer peer must be closed. Harness prints `[Harness] peer_check <slot>:
connected=<bool>` 60 ticks after the action. B-g: quitting just changed scene,
the client stayed connected, and the server kept streaming RPCs into an Arena
the client no longer had (log flood). T170: a refused rejoin must leave no
'Unable to send packet' on the host (B64).
"""
import glob
import os
import re

from . import base

NAME = "peer_closed"


def _died_while_away(ctx, new_id):
    """T555 (chaos_20 / chaos_22): the bot flew the rejoiner's mech meanwhile and it died -> the rejoiner
    rightly gets the mech picker (spectating), not its mech. True when the server log says `new_id` took
    back an old peer's slot and a mech that old peer owned died on the server."""
    run_dir = ctx.get("run_dir") or ""
    try:
        text = open(os.path.join(run_dir, "server.log"), errors="replace").read()
    except OSError:
        return False
    m = re.search(r"\[Arena\] rejoin: peer %d takes back the slot of (\d+)" % new_id, text)
    server = (ctx.get("primary") or {}).get("server")
    if m is None or server is None:
        return False
    old = int(m.group(1))
    mine = {s["mech_id"] for s in server.snaps if s.get("owner") in (old, new_id)}
    return any(e.get("type") == "died" and e.get("mech_id") in mine for e in server.events)


def run(ctx):
    logs = sorted(glob.glob(os.path.join(ctx.get("run_dir") or "", "*.log")))
    quits, bad = 0, []
    for path in logs:
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        if not re.search(r"\[Harness\] action (pause_quit|quit_to_hangar)", text):
            continue
        quits += 1
        m = re.search(r"\[Harness\] peer_check \S+: connected=(\w+) scene=(\S+)", text)
        if m is None:
            bad.append("%s: no peer_check after quit (process ended too soon?)" % role)
        elif m.group(1) != "false":
            bad.append("%s: still connected 60 ticks after quitting" % role)
        elif m.group(2) != "Hangar":  # T186: 'quit to hangar' means the hangar, MP too
            bad.append("%s: on %s after quitting a match, not the Hangar" % (role, m.group(2)))
    # T153 (V40 exception): server gone -> peer torn down, back at the title
    for path in logs:
        role = os.path.basename(path)[: -len(".log")]
        text = open(path, errors="replace").read()
        for m in re.finditer(r"\[Harness\] server_lost_check \S*: connected=(\w+) scene=(\S+) rejoin=(\w+)", text):
            quits += 1
            # T168/T170: a refused rejoin lands on MPEntry (reason sent during auth); host loss on the title
            want = "MPEntry" if m.group(3) == "true" else "TitleScreen"
            if m.group(1) != "false" or m.group(2) != want:
                bad.append("%s: %s 90 frames after losing the server (connected=%s), not %s"
                           % (role, m.group(2), m.group(1), want))
        # T206: a rejoin within Arena.HOLD_S takes the old slot back (was: refused, T170)
        if "[Harness] action rejoin" in text:
            m = re.search(r"\[Harness\] rejoined peer=(\d+) mech=(\S+) spectating=(\w+)", text)
            if m is None:
                bad.append("%s: rejoin never got back into the match" % role)
            elif m.group(2) == "none" and not _died_while_away(ctx, int(m.group(1))):
                bad.append("%s: rejoined but did not get its mech back (spectating=%s)" % (role, m.group(3)))
    # T167: host SIGKILLed -> every client must notice (peer timeout) and print its server_lost_check
    srv = os.path.join(ctx.get("run_dir") or "", "server.log")
    # T558: a link that went dark (scenario expect_server_lost) -> every client left on its own (silence)
    if (ctx.get("scenario") or {}).get("expect_server_lost") or \
            os.path.exists(srv) and "[Harness] action kill_client" in open(srv, errors="replace").read():
        for path in logs:
            if os.path.basename(path).startswith("client") and "server_lost_check" not in open(path, errors="replace").read():
                quits += 1
                bad.append("%s never noticed the host died" % os.path.basename(path)[: -len(".log")])
    # T170 (B64) / T206: a rejoiner builds its Arena during auth, before it joins the
    # connected set, so no broadcast can hit it early. Each 'Unable to send packet' on the
    # host = a send to a half-closed peer (the pre-T170 kick logged 2-21 per run on `bad`).
    if os.path.exists(srv) and any("action rejoin" in open(p, errors="replace").read() for p in logs):
        n = open(srv, errors="replace").read().count("Unable to send packet")
        if n:
            bad.append("server sent %d packet(s) to a half-closed peer around the rejoin (B64)" % n)
    if not quits:
        return base.verdict(NAME, base.SKIP, note="no lifecycle quit in run")
    if bad:
        return base.verdict(NAME, base.FAIL, note="; ".join(bad))
    return base.verdict(NAME, base.PASS, note="%d quitting peer(s) disconnected" % quits)
