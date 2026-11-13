extends Node
# T401 probe (V62): the pinned account certificate. A connection to the pinned host is
# answered only when the server holds the identity whose certificate the game carries;
# another certificate, or none, gets nothing (never an unchecked connection). An unpinned
# host still connects (encrypted, unchecked).

func _fail(msg: String) -> void:
	push_error("[probe] account_pin: " + msg)

func _answered() -> bool:
	var r: Dictionary = await Game.account_request("127.0.0.1", 8971, {"op": "login", "email": "nobody@example.com", "password": "x"})
	return r.get("error") != "no answer from the server" and r.get("error") != "secure connection failed"

func _ready() -> void:
	for f in ["user://account_tls.key", "user://account_tls.crt"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var srv: Node = load("res://scripts/AccountServer.gd").new()
	add_child(srv)
	if not srv.start(8972):  # its own fresh identity -> user://account_tls.crt
		_fail("account endpoint did not start")
	var shipped := Game.account_pin_cert
	if not ResourceLoader.exists(shipped) or not load(shipped) is X509Certificate:
		_fail("the game carries no pinned certificate at %s" % shipped)
	if Game.account_pin_host != "lemon.limedaley.com":
		_fail("the pinned host is %s" % Game.account_pin_host)
	if not await _answered():
		_fail("an unpinned host (127.0.0.1) got no answer")
	Game.account_pin_host = "127.0.0.1"
	if await _answered():
		_fail("the pinned host answered with a certificate that is not the pinned one -- an impostor would be accepted")
	Game.account_pin_cert = "res://resources/no_such.crt"
	if await _answered():
		_fail("with no pinned certificate the pinned host was accepted unchecked")
	Game.account_pin_cert = "user://account_tls.crt"  # this server's own
	if not await _answered():
		_fail("the pinned host was refused although it holds the pinned identity")
	print("[probe] account_pin done")
	get_tree().quit(0)
