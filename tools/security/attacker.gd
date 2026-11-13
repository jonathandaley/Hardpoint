extends Node
# T290: hostile game client. Joins the LOCAL test server (tools/security/run_security.py
# starts it) as a guest, the way a real player would, then sends what a modified client
# could: forged damage, other players' input, junk squads, server-only RPCs, bad types.
# Loopback only (HOST is a constant). Lines: `[sec] <name>: OK | VULN <why>`.
#   godot --headless --path . res://tools/security/attacker.tscn -- --sec-port=N --sec-mode=attacker|victim
# victim = an honest signed-in player the attacks are aimed at; it reports what it sees.

const HOST := "127.0.0.1"
var _port := 0
var _mode := "attacker"
var _secs := 60.0

func _ready() -> void:
	if get_tree().current_scene == self:  # boot scene: hand over to a node that outlives scene changes
		var n := Node.new()
		n.set_script(get_script())
		n.name = "Sec"
		get_tree().root.add_child.call_deferred(n)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sec-port="):
			_port = int(a.get_slice("=", 1))
		elif a.begins_with("--sec-mode="):
			_mode = a.get_slice("=", 1)
		elif a.begins_with("--sec-secs="):
			_secs = float(a.get_slice("=", 1))
	if _port <= 0:
		print("[sec] usage: -- --sec-port=N --sec-mode=attacker|victim")
		get_tree().quit(2)
		return
	if _mode == "victim":
		_victim()
	elif _mode == "idler":
		_idler()
	else:
		_attacker()

func _say(check: String, why: String = "") -> void:
	print("[sec] %s: %s" % [check, "OK" if why == "" else "VULN " + why])

func _wait(s: float) -> void:
	await get_tree().create_timer(s, true).timeout

func _until(cond: Callable, timeout: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(timeout * 1000.0):
		if cond.call():
			return true
		await get_tree().process_frame
	return false

func _me() -> int:
	return multiplayer.get_unique_id()

func _arena() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.name == "Arena" else null

func _mechs() -> Array:
	var out: Array = []
	var a := _arena()
	if a == null:
		return out
	for t in 2:
		for m in a._team_mechs[t]:
			if is_instance_valid(m):
				out.append(m)
	return out

func _join_lobby() -> bool:
	Game.join(HOST, _port)
	if not await _until(func() -> bool: return multiplayer.get_peers().has(1), 20.0):
		print("[sec] could not join %s:%d" % [HOST, _port])
		return false
	get_tree().change_scene_to_file("res://scenes/ui/Lobby.tscn")
	await _until(func() -> bool: return Game.mp_lobby["peers"].has(_me()), 10.0)
	return true

func _in_match() -> bool:
	if not await _until(func() -> bool: return _arena() != null and Game.server_heard, 40.0):
		return false
	_arena().rpc_id(1, &"_rpc_keep_first")  # skip the start pick: reveal the first mech now
	await _wait(2.0)
	return true

# ---- the honest player ----

func _victim() -> void:
	var email := "victim%d@example.com" % (Time.get_ticks_usec() % 1000000)
	var reply: Dictionary = await Game.account_request(HOST, _port,
		{"op": "signup", "email": email, "password": "victim-password-1", "callsign": "Victim"})
	if not reply.get("ok", false):
		print("[victim] sign-up failed: %s" % reply)
		get_tree().quit(1)
		return
	Game.sign_in(HOST, _port, email, reply)
	print("[victim] email=%s token=%s" % [email, Game.player_token()])
	if not await _join_lobby():
		get_tree().quit(1)
		return
	print("[victim] id=%d" % _me())
	Game._rpc_set_ready.rpc_id(1, true)
	var t0 := Time.get_ticks_msec()
	var in_match := false
	while Time.get_ticks_msec() - t0 < int(_secs * 1000.0):
		await _wait(1.0)
		if not in_match and _arena() != null and Game.server_heard:
			in_match = true
			_arena().rpc_id(1, &"_rpc_keep_first")
		var bad := 0
		var mine := 0.0
		for m in _mechs():
			if not (m.global_position as Vector3).is_finite():
				bad += 1
			if int(m.owner_peer_id) == _me() and not m.is_dead:
				mine = m.health
		print("[victim] t=%d connected=%s scene=%s my_hp=%.0f nonfinite_mechs=%d lobby_peers=%d" % [
			(Time.get_ticks_msec() - t0) / 1000, multiplayer.get_peers().has(1),
			get_tree().current_scene.name if get_tree().current_scene != null else "-", mine, bad,
			Game.mp_lobby["peers"].size()])
	print("[victim] done")
	get_tree().quit(0)

# ---- T400: the player who joins and never readies up (holding the lobby hostage) ----

func _idler() -> void:
	if not await _join_lobby():
		get_tree().quit(1)
		return
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(_secs * 1000.0):
		await _wait(1.0)
		var a := _arena()
		var own := 0
		for m in _mechs():
			own += 1 if int(m.owner_peer_id) == _me() else 0
		print("[idler] t=%d connected=%s scene=%s own_mechs=%d watching=%s sitting_out=%s" % [
			(Time.get_ticks_msec() - t0) / 1000, multiplayer.get_peers().has(1),
			get_tree().current_scene.name if get_tree().current_scene != null else "-", own,
			a != null and is_instance_valid(a._spectated_mech),
			Game.mp_lobby["peers"].get(_me(), {}).get("sitting_out", false)])
	print("[idler] done")
	get_tree().quit(0)

# ---- the attacker ----

func _attacker() -> void:
	if not await _join_lobby():
		get_tree().quit(1)
		return
	await _until(func() -> bool: return Game.mp_lobby["peers"].size() >= 2, 15.0)
	await _wait(1.0)
	await _lobby_attacks()
	# an honest squad again, then ready up -> the match starts
	Game._rpc_set_squad.rpc_id(1, load("res://scripts/Lobby.gd")._build_squad_data())
	Game._rpc_set_ready.rpc_id(1, true)
	if not await _in_match():
		_say("reach_match", "the attacker never reached a live match (lobby state: %s)" % str(Game.mp_lobby).left(300))
		print("[sec] done")
		get_tree().quit(0)
		return
	await _match_attacks()
	print("[sec] done")
	await _wait(_secs)  # stay connected: the raw-protocol attacks run against a live match
	get_tree().quit(0)

func _others() -> Dictionary:
	var out := {}
	for pid in Game.mp_lobby["peers"]:
		if int(pid) != _me():
			out[pid] = Game.mp_lobby["peers"][pid]
	return out

func _lobby_attacks() -> void:
	# 1. what the server tells us about OTHER players
	var leaked: Array = []
	for pid in _others():
		for k in ["token", "account", "session", "email"]:
			if String(_others()[pid].get(k, "")) != "":
				leaked.append("%s=%s" % [k, _others()[pid][k]])
	_say("lobby_private_fields", "" if leaked.is_empty() else "the lobby broadcast gives every client other players' %s" % ", ".join(leaked))

	# 2. server-only RPCs sent by a client (the engine must refuse them)
	Game._rpc_sync_lobby.rpc_id(1, {"peers": {}, "bot_fill": false, "team_size": 6, "map_path": "res://x", "match_seed": 1})
	Game._rpc_change_scene.rpc_id(1, "res://scenes/ui/TitleScreen.tscn")
	Game._rpc_match_end.rpc_id(1, 0, [])
	Game._rpc_account_profile.rpc_id(1, {"coins": 999999})
	await _wait(1.0)
	Game._rpc_set_ready.rpc_id(1, false)  # makes the server rebroadcast its real lobby
	await _wait(1.0)
	var ts: int = int(Game.mp_lobby.get("team_size", 0))
	_say("server_only_rpc", "" if multiplayer.get_peers().has(1) and ts != 6 and Game.mp_lobby["peers"].size() >= 2
		else "a client-sent server RPC changed the server (team_size %d, peers %d)" % [ts, Game.mp_lobby["peers"].size()])

	# 3. squad: something that is not a mech, extra payload, weapons that are not weapons
	var junk: Array = []
	for i in 5:
		junk.append({"mech": "res://scenes/arena/Arena.tscn", "weapons": [], "junk": "A".repeat(20000)})
	Game._rpc_set_squad.rpc_id(1, junk)
	await _wait(1.0)
	var sq: Array = Game.mp_lobby["peers"].get(_me(), {}).get("squad", [])
	var why := ""
	if not sq.is_empty() and String(sq[0].get("mech", "")) == "res://scenes/arena/Arena.tscn":
		why = "the server accepted a squad whose 'mech' is the Arena scene"
	if not sq.is_empty() and sq[0].has("junk"):
		why += " and rebroadcast 20 KB of extra payload per slot to every client"
	_say("squad_not_a_mech", why)

	var honest: Array = load("res://scripts/Lobby.gd")._build_squad_data()
	var dbg: Array = honest.duplicate(true)
	dbg[0] = {"mech": "res://resources/mechs/DebugMech.tres", "weapons": []}
	Game._rpc_set_squad.rpc_id(1, dbg)
	await _wait(1.0)
	sq = Game.mp_lobby["peers"].get(_me(), {}).get("squad", [])
	_say("squad_debug_mech", "the server accepted the debug mech (not in the hangar) in a squad" if not sq.is_empty()
		and String(sq[0].get("mech", "")).contains("DebugMech") else "")
	var odd: Array = honest.duplicate(true)
	odd[0]["weapons"] = ["res://scenes/ui/Lobby.tscn", "res://scenes/ui/Lobby.tscn", "res://scenes/ui/Lobby.tscn",
		"res://scenes/ui/Lobby.tscn", "res://scenes/ui/Lobby.tscn", "res://scenes/ui/Lobby.tscn"]
	Game._rpc_set_squad.rpc_id(1, odd)
	await _wait(1.0)
	sq = Game.mp_lobby["peers"].get(_me(), {}).get("squad", [])
	_say("squad_not_a_weapon", "the server accepted a UI scene as a weapon" if not sq.is_empty()
		and (sq[0].get("weapons", []) as Array).has("res://scenes/ui/Lobby.tscn") else "")

	# 4. profile claims
	var all_skills := {}
	for k in Game.SKILL_TREE:
		all_skills[k] = 99
	Game._rpc_send_meta.rpc_id(1, {"pilot_name": "[b]Evil[/b]\n".repeat(2000), "elo": 999999, "level": 9999, "skills": all_skills})
	await _wait(1.0)
	var mine: Dictionary = Game.mp_lobby["peers"].get(_me(), {})
	var nm := String(mine.get("pilot_name", ""))
	why = ""
	if nm.length() > 24 or nm.contains("\n") or nm.contains("["):
		why = "pilot name stored as sent (%d chars, markup / newlines)" % nm.length()
	_say("meta_name", why)
	_say("meta_claims", "" if int(mine.get("elo", 0)) <= 4000 and int(mine.get("level", 0)) <= 100
		else "a guest's claimed ELO %d / level %d / %d skills are taken as sent" % [int(mine.get("elo", 0)),
			int(mine.get("level", 0)), (mine.get("skills", {}) as Dictionary).size()])
	# T399: on a dedicated server a guest flies with no skills at all (its profile is its own claim)
	_say("guest_skills", "" if (mine.get("skills", {}) as Dictionary).is_empty()
		else "a guest's claimed skills were accepted on a dedicated server: %s" % str(mine.get("skills")).left(80))
	Game._rpc_send_meta.rpc_id(1, {"pilot_name": "Mallory", "elo": 1000, "level": 1, "skills": {}})

	# 5. wrong types / shapes: must not break the server (checked from its log + liveness)
	Game._rpc_set_squad.rpc_id(1, [1, 2, 3, 4, 5])
	Game._rpc_set_squad.rpc_id(1, [{"mech": 5, "weapons": "x"}, {}, {}, {}, {}])
	Game._rpc_send_meta.rpc_id(1, {"elo": {"a": 1}, "level": [1], "skills": "x", "pilot_name": {"x": 1}})
	Game.rpc_id(1, &"_rpc_set_ready", "yes")
	Game.rpc_id(1, &"_rpc_set_ready")
	Game.rpc_id(1, &"_rpc_set_squad", 1, 2, 3)
	for i in 200:  # lobby churn: each one makes the server rebroadcast to everyone
		Game._rpc_set_ready.rpc_id(1, i % 2 == 0)
	await _wait(1.5)
	_say("lobby_bad_types", "" if multiplayer.get_peers().has(1) else "the server dropped us / died on malformed lobby RPCs")

func _match_attacks() -> void:
	var mine: Node = null
	var foes: Array = []
	for m in _mechs():
		if int(m.owner_peer_id) == _me() and not m.is_dead:
			mine = m
		elif not m.is_dead:
			foes.append(m)
	if mine == null or foes.is_empty():
		_say("match_setup", "no own mech / no other mechs to aim at (mechs: %d)" % _mechs().size())
		return

	# 1. drive somebody else's mech
	for f in foes:
		f.rpc_id(1, &"_rpc_input", 999999, {"move": Vector2(1, 0), "aim": Vector2.ZERO, "fire_prim": true,
			"fire_sec": true, "presses": [1, 1, 1, 1, 1, 1]})

	# 2. forged damage: nothing on a client ever legitimately deals damage (V30 / V38).
	# (Once the server has no such RPC, this client has none either and the call fails
	# locally -- the static net_security oracle keeps the RPC from coming back.)
	var before := {}
	for f in foes:
		before[f] = float(f.health)
		f.rpc_id(1, &"_take_damage_rpc", 1.0e9, NodePath())
	await _wait(1.5)
	var killed := 0
	for f in foes:
		if not is_instance_valid(f) or f.is_dead or float(f.health) < float(before[f]):
			killed += 1
	_say("forged_damage", "" if killed == 0 else "a client's damage RPC hit %d of %d other mechs (instant kill of anyone)" % [killed, foes.size()])

	# 3. negative damage on our own mech = a heal
	if is_instance_valid(mine) and not mine.is_dead:
		var hp0 := float(mine.health)
		mine.rpc_id(1, &"_take_damage_rpc", -5000.0, NodePath())
		await _wait(1.0)
		_say("forged_heal", "" if float(mine.health) <= maxf(hp0, float(mine.max_health)) + 1.0
			else "negative damage raised our mech from %.0f to %.0f HP (max %.0f)" % [hp0, float(mine.health), float(mine.max_health)])

	# 4. input: not-a-number / infinite / oversized values on our own mech
	if is_instance_valid(mine) and not mine.is_dead:
		for i in 30:
			mine.rpc_id(1, &"_rpc_input", 100000 + i, {"move": Vector2(NAN, NAN), "aim": Vector2(INF, NAN),
				"shoulder": NAN, "fire_prim": false, "fire_sec": false, "presses": [0, 0, 0, 0, 0, 0]})
			await get_tree().physics_frame
		await _wait(0.5)
		var p0: Vector3 = _server_pos(mine)
		for i in 60:  # 1 s of "move at 1000x"
			mine.rpc_id(1, &"_rpc_input", 200000 + i, {"move": Vector2(1000.0, 0.0), "aim": Vector2.ZERO,
				"shoulder": 1.0e30, "fire_prim": false, "fire_sec": false, "presses": [0, 0, 0, 0, 0, 0]})
			await get_tree().physics_frame
		await _wait(0.3)
		var p1: Vector3 = _server_pos(mine)
		var why := ""
		if not p0.is_finite() or not p1.is_finite():
			why = "NaN input put our mech at a non-finite position on the server (%s)" % p1
		elif Vector2(p1.x - p0.x, p1.z - p0.z).length() > float(mine.walk_speed) * 1.3 * 2.0 + 1.0:
			why = "oversized move input moved %.1f m in ~1.3 s (walk speed %.1f m/s)" % [
				Vector2(p1.x - p0.x, p1.z - p0.z).length(), float(mine.walk_speed)]
		_say("input_values", why)
		# malformed payload shapes
		mine.rpc_id(1, &"_rpc_input", 300000, {"move": "x", "aim": "y", "fire_prim": "z", "presses": "q", "shoulder": {}})
		mine.rpc_id(1, &"_rpc_input", 300001, {"presses": [1.0e308, -1, 2, 3, 4, 5]})
		mine.rpc_id(1, &"_rpc_input", "seq", [])
		mine.rpc_id(1, &"_rpc_input")

	# 5. picks we have no right to
	var a := _arena()
	for args in [[0, 0], [-1, -1], [999999, 999999], [1, 0], [1, 0], [2, 0], [3, 0], [4, 0]]:
		a.rpc_id(1, &"_rpc_pick_next_mech", args[0], args[1])
		a.rpc_id(1, &"_rpc_start_pick", args[0], args[1])
	await _wait(1.0)
	var live := 0
	for m in _mechs():
		if int(m.owner_peer_id) == _me() and not m.is_dead:
			live += 1
	_say("extra_mechs", "" if live <= 1 else "pick RPCs gave us %d live mechs at once" % live)

	# 6. server-only match RPCs from a client
	a.rpc_id(1, &"_rpc_spawn_pickup", 9999, "coins", Vector3.ZERO, 999999)
	a.rpc_id(1, &"_rpc_reassign", foes[0].owner_peer_id, _me())
	a.rpc_id(1, &"_rpc_kill_feed", 0, 0)
	Game._rpc_match_end.rpc_id(1, 0, [{"peer_id": _me(), "coins": 999999}])
	if is_instance_valid(foes[0]):
		foes[0].rpc_id(1, &"_sync_death")
		foes[0].rpc_id(1, &"_sync_health", 1.0)
	await _wait(1.5)
	_say("match_alive", "" if multiplayer.get_peers().has(1) and _arena() != null else "the match / connection did not survive the attack run")

func _server_pos(m: Node) -> Vector3:
	var buf = m.get("_snap_buf")
	if buf is Array and not (buf as Array).is_empty():
		return (buf as Array)[-1]["pos"]
	return m.global_position
