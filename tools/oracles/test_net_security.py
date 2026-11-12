"""Red-before-green for the net_security oracle: each rule fails on a known-bad script."""
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from oracles import net_security as ns

GOOD = '''@rpc("any_peer", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
'''
CASES = {
    "new any_peer RPC": '@rpc("any_peer")\nfunc _rpc_gift(n: int) -> void:\n\tif multiplayer.is_server():\n\t\tvar s := multiplayer.get_remote_sender_id()\n',
    "no is_server": '@rpc("any_peer")\nfunc _rpc_set_ready(r: bool) -> void:\n\tvar s := multiplayer.get_remote_sender_id()\n',
    "no sender": '@rpc("any_peer")\nfunc _rpc_set_ready(r: bool) -> void:\n\tif not multiplayer.is_server():\n\t\treturn\n',
    "push_error refusal": GOOD + '\tpush_error("bad")\n',
    "object decoding": 'func f(b):\n\treturn bytes_to_var_with_objects(b)\n',
    "bytes_to_var elsewhere": 'func f(b):\n\treturn bytes_to_var(b)\n',
    "exec": 'func f():\n\tOS.execute("sh", [])\n',
    "unsafe tls": 'func f():\n\treturn TLSOptions.client_unsafe()\n',
    "session in the hello": 'func _on_mp_peer_authenticating(id):\n\tvar hello = "token:" + account["session"]\n',
    "bare conversion": GOOD.replace("_rpc_set_ready(ready: bool)", "_rpc_send_meta(meta: Dictionary)") + '\tvar e := int(meta.get("elo", 0))\n',
}


def main():
    fails = 0
    if ns.scan([("scripts/X.gd", GOOD)]):
        print("FAIL good script flagged: %s" % ns.scan([("scripts/X.gd", GOOD)]))
        fails += 1
    for name, text in CASES.items():
        if not ns.scan([("scripts/X.gd", text)]):
            print("FAIL not caught: %s" % name)
            fails += 1
    real = ns.scan()
    if real:
        print("FAIL the repo itself: %s" % real)
        fails += 1
    print("test_net_security: %s" % ("OK" if not fails else "%d FAILED" % fails))
    return fails


if __name__ == "__main__":
    sys.exit(main())
