"""net_security oracle (T384, V61 / V62): static scan, no run data. The rules that keep
the game safe to put on the internet, checked on every suite run so a later task cannot
quietly break them (tools/security/run_security.py is the dynamic half: it attacks a
real server).

1. Every `@rpc("any_peer")` function is on ANY_PEER_OK. A new client-callable RPC fails
   here until someone adds it to the list AND to tools/security/attacker.gd.
2. Every any_peer handler checks `multiplayer.is_server()` and reads
   `get_remote_sender_id()` in its own body (V41): who is asking is never a parameter.
3. Game code never decodes objects from the network, never evaluates text as code, never
   starts processes: BANNED below. `bytes_to_var(` only at the audited sites in VAR_OK.
   The hello never carries an account session (T385: single-use join tickets).
4. Handlers of client input never `push_error` a refusal (Game.net_refuse: rate-limited),
   and never convert a client's value with a bare `String(` / `int(` / `float(` /`str(`
   on `.get(` of the payload -- the type must be checked first (clean_int, clean_name,
   `is String`, typeof).
5. T388: the hash of every @rpc signature is recorded with Game.NET_VERSION (NET_SIG).
   Change an RPC and this fails until NET_VERSION is bumped and NET_SIG updated
   (`python3 -m oracles.net_security` in tools/ prints the new pair).
"""
import glob
import hashlib
import os
import re

from . import base

NAME = "net_security"

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAME_DIRS = ("autoloads", "scripts", "scenes", "shaders")

# Client-callable RPCs. Each one is attacked by tools/security/attacker.gd.
ANY_PEER_OK = {
    "_rpc_send_meta", "_rpc_transition_ack", "_rpc_set_squad", "_rpc_set_ready", "_rpc_ready_for_next",  # Game
    "_rpc_self_destruct", "_rpc_pick_next_mech", "_rpc_keep_first", "_rpc_start_pick",                    # Arena
    "_rpc_input",                                                                                         # Mech
}

BANNED = {
    "bytes_to_var_with_objects(": "decodes objects (code) from bytes",
    "var_to_bytes_with_objects(": "encodes objects into packets",
    "str_to_var(": "parses text into arbitrary Variants",
    "allow_object_decoding": "lets peers send objects",
    "Expression.new(": "evaluates text as code",
    "OS.execute(": "starts a process",
    "OS.create_process(": "starts a process",
    "OS.shell_open(": "opens a URL / file with the system handler",
    "client_unsafe(": None,  # allowed only at TLS_UNSAFE_OK
}
VAR_OK = {("autoloads/Game.gd", "_on_mp_auth")}       # client decoding the server's late-join state
TLS_UNSAFE_OK = {("autoloads/Game.gd", "_account_tls")}  # unofficial servers only; the official host is pinned (T401)

NET_SIG = (2, "1fb95d0f66a04ff7")  # (Game.NET_VERSION, rpc_hash()) -- change both together, never the hash alone

_SIG = re.compile(r'@rpc\(([^)]*)\)\s*\n\s*func\s+(\w+)\s*\(([^)]*)\)')
_FUNC = re.compile(r'^(?:static\s+)?func\s+(\w+)\s*\(', re.M)
_RPC = re.compile(r'@rpc\(([^)]*)\)\s*\n\s*func\s+(\w+)')
_BARE = re.compile(r'\b(?:String|int|float|str)\(\s*(?:payload|meta|req|entry)\.get\(')


def game_files():
    for d in GAME_DIRS:
        for path in sorted(glob.glob(os.path.join(REPO, d, "**", "*.gd"), recursive=True)):
            yield os.path.relpath(path, REPO).replace(os.sep, "/"), open(path, errors="replace").read()


def functions(text):
    """{name: body text} for the top-level functions of one script."""
    hits = list(_FUNC.finditer(text))
    return {m.group(1): text[m.start():(hits[i + 1].start() if i + 1 < len(hits) else len(text))]
            for i, m in enumerate(hits)}


def rpc_hash(files=None):
    """One hash over every @rpc function's script, mode, name and parameters."""
    sigs = sorted("%s|%s|%s|%s" % (rel, re.sub(r'\s+', '', a), f, re.sub(r'\s+', '', params))
                  for rel, text in (files if files is not None else game_files())
                  for a, f, params in _SIG.findall(text))
    return hashlib.sha256("\n".join(sigs).encode()).hexdigest()[:16]


def net_version():
    m = re.search(r'^const NET_VERSION := (\d+)', open(os.path.join(REPO, "autoloads", "Game.gd")).read(), re.M)
    return int(m.group(1)) if m else -1


def scan(files=None):
    """[problem text]; `files` = [(relative path, text)] for the self-test."""
    bad = []
    for rel, text in (files if files is not None else game_files()):
        funcs = functions(text)
        any_peer = [f for args, f in _RPC.findall(text) if "any_peer" in args]
        for f in any_peer:
            body = funcs.get(f, "")
            if f not in ANY_PEER_OK:
                bad.append("%s %s: new client-callable RPC -- add it to ANY_PEER_OK and attack it in tools/security/attacker.gd" % (rel, f))
            if "multiplayer.is_server()" not in body:
                bad.append("%s %s: any_peer handler without an is_server() check" % (rel, f))
            if "get_remote_sender_id()" not in body:
                bad.append("%s %s: any_peer handler never reads get_remote_sender_id()" % (rel, f))
            if "push_error(" in body:
                bad.append("%s %s: refuses client input with push_error (use Game.net_refuse)" % (rel, f))
        for name, body in funcs.items():
            for needle, why in BANNED.items():
                if needle in body:
                    if needle == "client_unsafe(" and (rel, name) in TLS_UNSAFE_OK:
                        continue
                    bad.append("%s %s: %s -- %s" % (rel, name, needle.rstrip("("), why or "TLS without certificate checking"))
            if re.search(r'\bbytes_to_var\(', body) and (rel, name) not in VAR_OK:
                bad.append("%s %s: bytes_to_var outside the audited sites (VAR_OK)" % (rel, name))
            if name == "_on_mp_peer_authenticating" and "session" in body:
                bad.append("%s %s: an account session on the game connection (unencrypted; join tickets only, T385)" % (rel, name))
            if (name in any_peer or name in ("push_input", "handle")) and _BARE.search(body):
                bad.append("%s %s: converts a client's value without checking its type first" % (rel, name))
    if files is None and (net_version(), rpc_hash()) != NET_SIG:
        bad.append("an @rpc signature or Game.NET_VERSION changed: bump NET_VERSION (old clients must be told to update) "
                   "and set NET_SIG = (%d, \"%s\") with the bumped version (T388)" % (net_version(), rpc_hash()))
    return bad


def run(ctx):
    bad = scan()
    if bad:
        return base.verdict(NAME, base.FAIL, note="%d network-security rule violations (V61/V62): %s" % (len(bad), "; ".join(bad[:6])))
    return base.verdict(NAME, base.PASS, note="any_peer RPCs classified + guarded, no object decoding / eval / exec (V61, V62)")


if __name__ == "__main__":
    print("NET_SIG = (%d, \"%s\")" % (net_version(), rpc_hash()))
