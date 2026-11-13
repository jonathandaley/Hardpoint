extends Node
# T400 probe: a dedicated server's lobby must not be held hostage by a player who never
# readies up -- and must not start without one who is only slow. Also the ban list.

func _fail(msg: String) -> void:
	push_error("[probe] lobby_idle: " + msg)

func _peer(ready: bool) -> Dictionary:
	return {"pilot_name": "P", "elo": 1000, "level": 1, "squad": [], "ready": ready}

func _ready() -> void:
	Game.dedicated = true
	Game._min_players = 2
	Game.mp_lobby["team_size"] = 3
	var peers: Dictionary = Game.mp_lobby["peers"]
	peers.clear()
	# not enough ready players: nobody is being waited on, nothing starts
	peers[2] = _peer(true)
	peers[3] = _peer(false)
	peers[4] = _peer(false)
	Game._dedicated_lobby_changed()
	if Game.mp_lobby.get("starting") or int(Game.mp_lobby.get("idle_wait", 0)) != 0 or not Game._waiting_since.is_empty():
		_fail("1 of 3 ready with min-players 2: starting=%s idle_wait=%s" % [Game.mp_lobby.get("starting"), Game.mp_lobby.get("idle_wait")])
	# enough ready: the unready one gets the full wait, the match does not start yet
	peers[3]["ready"] = true
	Game._dedicated_lobby_changed()
	if Game.mp_lobby.get("starting") or int(Game.mp_lobby.get("idle_wait", 0)) != int(Game.lobby_idle_s) or Game.lobby_idle_s < 120.0:
		_fail("2 of 3 ready: starting=%s idle_wait=%s (wait %.0f s)" % [Game.mp_lobby.get("starting"), Game.mp_lobby.get("idle_wait"), Game.lobby_idle_s])
	# other lobby changes do not restart its clock; a slow player is still waited for
	Game._waiting_since[4] -= int(Game.lobby_idle_s * 1000.0) - 5000
	Game._dedicated_lobby_changed()
	if Game.mp_lobby.get("starting") or peers[4].get("sitting_out", false) or int(Game.mp_lobby.get("idle_wait", 0)) > 5:
		_fail("5 s before the limit: starting=%s sitting_out=%s idle_wait=%s" % [Game.mp_lobby.get("starting"), peers[4].get("sitting_out"), Game.mp_lobby.get("idle_wait")])
	# past the limit: it sits out, the match starts without it and it is not in the roster
	Game._waiting_since[4] -= 6000
	Game._dedicated_lobby_changed()
	var roster: Array = load("res://scripts/Lobby.gd")._build_roster()
	var in_match: Array = roster.map(func(e): return int(e["peer_id"])).filter(func(p): return p > 0)
	in_match.sort()
	if not Game.mp_lobby.get("starting") or not peers[4].get("sitting_out", false) or in_match != [2, 3]:
		_fail("past the limit: starting=%s sitting_out=%s roster peers %s" % [Game.mp_lobby.get("starting"), peers[4].get("sitting_out"), in_match])
	# it stays out (no fresh 3 minutes every match) until it readies up
	peers[2]["ready"] = false
	Game._dedicated_lobby_changed()
	peers[2]["ready"] = true
	Game._dedicated_lobby_changed()
	if not Game.mp_lobby.get("starting"):
		_fail("a player who sat out held up the next start again")
	Game._apply_ready(4, true)
	if peers[4].has("sitting_out"):
		_fail("readying up did not bring the player back in")
	Game._countdown_id += 1  # cancel the pending start: this probe has no match to run
	# ban list: an address or an account email a line, comments and case ignored
	var f := FileAccess.open(Game.BAN_FILE, FileAccess.WRITE)
	f.store_string("# troublemakers\n203.0.113.9\n  Mallory@Example.com \n\n")
	f.close()
	for c in [["203.0.113.9", true], ["mallory@example.com", true], ["203.0.113.90", false], ["", false], ["# troublemakers", false], ["ace@example.com", false]]:
		if Game._banned(c[0]) != c[1]:
			_fail("_banned(%s) != %s" % [c[0], c[1]])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.BAN_FILE))
	if Game._banned("203.0.113.9"):
		_fail("banned with no ban file")
	print("[probe] lobby_idle done")
	get_tree().quit(0)
