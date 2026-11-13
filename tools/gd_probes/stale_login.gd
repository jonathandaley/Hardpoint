extends Node
# T403 probe: the account server restarted (sessions live in its memory), the player's game
# stayed open. Joining that server or buying a skill must sign them out and say why --
# never a silent guest join. Control: a live session still gets its join ticket.

const GAME_PORT := 8980  # account endpoint = +1

func _fail(msg: String) -> void:
	push_error("[probe] stale_login: " + msg)

func _notice() -> String:  # Game.get: the probe also runs (red) on code without it
	var n = Game.get("account_notice")
	return n if n is String else ""

func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://accounts.cfg"))
	var srv: Node = load("res://scripts/AccountServer.gd").new()
	add_child(srv)
	if not srv.start(GAME_PORT + 1):
		_fail("account endpoint did not start")
	var r: Dictionary = srv.handle(JSON.stringify({"op": "signup", "email": "ace@example.com", "password": "hunter2-but-longer", "callsign": "Ace"}))
	var failed := [0]
	Game.mp_join_failed.connect(func() -> void: failed[0] += 1)
	# control: a live session gets a ticket and joins as itself
	Game.sign_in("127.0.0.1", GAME_PORT, "ace@example.com", r)
	await Game.join("127.0.0.1", GAME_PORT)
	if Game._join_ticket == "" or Game.account.is_empty() or _notice() != "":
		_fail("live session: ticket '%s', account %s, notice '%s'" % [Game._join_ticket, Game.account, _notice()])
	Game.disconnect_mp()
	# the server forgot every session (a restart)
	Game.account["session"] = "0".repeat(64)
	await Game.join("127.0.0.1", GAME_PORT)
	if not Game.account.is_empty() or _notice() == "" or failed[0] != 1 \
			or Game.multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		_fail("stale session on join: account %s, notice '%s', join_failed %d, peer %s"
			% [Game.account, _notice(), failed[0], Game.multiplayer.multiplayer_peer])
	Game.disconnect_mp()
	# a skill purchase with a stale session: signed out + told too
	Game.set("account_notice", "")
	Game.sign_in("127.0.0.1", GAME_PORT, "ace@example.com", r)
	Game.account["session"] = "0".repeat(64)
	var ok: bool = await Game.account_skill("unlock_skill", Game.SKILL_TREE.keys()[0])
	if ok or not Game.account.is_empty() or _notice() == "":
		_fail("stale session on a skill: ok %s, account %s, notice '%s'" % [ok, Game.account, _notice()])
	print("[probe] stale_login done")
	get_tree().quit(0)
