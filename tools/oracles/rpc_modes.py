"""rpc_modes oracle (T151, V44): static scan, no run data. Every
`@rpc(... unreliable ...)` in the game must be on the allow-list below --
streams that self-correct on the next send, or cosmetic one-shots where a loss
only means a missing effect. Change-driven STATE must be reliable: a dropped
final packet never self-corrects (B49: unreliable _sync_health left a client
showing 55 HP for 10 s under 1% loss). A new unreliable RPC fails here until
someone classifies it.
"""
import glob
import os
import re

from . import base

NAME = "rpc_modes"

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

UNRELIABLE_OK = {
    # streams: resent continuously, newest wins
    "_rpc_snapshot", "_rpc_input", "_sync_scores", "_sync_progress", "_sync_lock_progress",
    # cosmetic one-shots: a loss is a missing effect, never wrong state
    "_rpc_beam_fx", "_rpc_shot_fx", "_rpc_spawn_ghost", "_rpc_pellet_ghosts", "_rpc_play_sfx", "_rpc_play_sfx_2d",
    "_rpc_muzzle_flash", "_rpc_tracer", "_rpc_hit_sparks", "_rpc_death_explosion",
}

_RPC = re.compile(r'@rpc\(([^)]*)\)\s*\n\s*func\s+(\w+)')


def scan():
    """[(path, func)] of unreliable RPCs not on the allow-list."""
    bad = []
    for path in sorted(glob.glob(os.path.join(REPO, "**", "*.gd"), recursive=True)):
        if os.sep + "build" + os.sep in path or os.sep + ".godot" + os.sep in path:
            continue
        with open(path, errors="replace") as f:
            for args, func in _RPC.findall(f.read()):
                if "unreliable" in args and func not in UNRELIABLE_OK:
                    bad.append((os.path.relpath(path, REPO), func))
    return bad


def run(ctx):
    bad = scan()
    if bad:
        return base.verdict(NAME, base.FAIL, note="unreliable RPC not classified as stream/cosmetic (V44): " +
                            ", ".join("%s %s" % b for b in bad))
    return base.verdict(NAME, base.PASS, note="every unreliable RPC is a stream or cosmetic (V44)")
