extends Node
# T476 probe (HUMAN_FOUND 2026-11-18/19: "Team selection" / "Multiplayer should allow picking teams. Also
# named Elite bots, as well as specific difficulty for each slot."): the roster honours team wishes while
# a side has room (the rest overflow), AUTO players balance the sides, the host's bot slots set each
# bot's difficulty and name an Elite; the lobby's TEAM menu sets the host's own wish.

const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] lobby_teams FAIL: " + msg)
	get_tree().quit(1)

func _peer(pref: int) -> Dictionary:
	return {"pilot_name": "P", "squad": [], "ready": true, "team_pref": pref}

func _teams(roster: Array) -> Dictionary:
	var out := {}
	for e in roster:
		if int(e["peer_id"]) != 0:
			out[int(e["peer_id"])] = int(e["team"])
	return out

func _ready() -> void:
	var bad: Array = []
	Game.mp_lobby = {"peers": {11: _peer(1), 12: _peer(1), 13: _peer(-1), 14: _peer(0)}, "team_size": 2, "bot_fill": true, "mode": "beacons"}
	var t := _teams(Lobby._build_roster())
	if t != {11: 1, 12: 1, 13: 0, 14: 0}:
		bad.append("wishes B,B,AUTO,A in 2v2 gave %s" % str(t))
	Game.mp_lobby = {"peers": {11: _peer(0), 12: _peer(0)}, "team_size": 1, "bot_fill": true, "mode": "beacons"}
	t = _teams(Lobby._build_roster())
	if t != {11: 0, 12: 1}:
		bad.append("two A wishes in 1v1 gave %s (the second overflows to B)" % str(t))
	Game.mp_lobby = {"peers": {11: _peer(-1), 12: _peer(-1), 13: _peer(-1)}, "team_size": 3, "bot_fill": true, "mode": "beacons"}
	t = _teams(Lobby._build_roster())
	if t != {11: 0, 12: 1, 13: 0}:
		bad.append("three AUTO players gave %s (want the old alternation)" % str(t))
	var elite: String = load("res://scripts/BotNames.gd").ELITE_KIT.keys()[0]
	Game.mp_lobby = {"peers": {11: _peer(0)}, "team_size": 3, "bot_fill": true, "mode": "beacons",
		"bot_setup": [[{"d": 1, "e": ""}, {"d": 4, "e": elite}], [{"d": 3, "e": ""}, {"d": "x", "e": 7}, {"d": 99, "e": "Nobody"}]]}
	var r := Lobby._build_roster()
	var a_bots := r.filter(func(e): return int(e["peer_id"]) == 0 and int(e["team"]) == 0)
	var b_bots := r.filter(func(e): return int(e["peer_id"]) == 0 and int(e["team"]) == 1)
	if a_bots.size() != 2 or int(a_bots[0].get("difficulty", -1)) != 1 or a_bots[1].get("name") != elite or int(a_bots[1].get("difficulty", -1)) != 4:
		bad.append("team A's bot slots came out %s" % str(a_bots.map(func(e): return [e.get("name"), e.get("difficulty", -1)])))
	if b_bots.size() != 3 or int(b_bots[0].get("difficulty", -1)) != 3 or b_bots[1].has("difficulty") or int(b_bots[2].get("difficulty", -1)) != 4 or b_bots[2].has("elite"):
		bad.append("team B's slots (3, junk, 99 + unknown name) came out %s" % str(b_bots.map(func(e): return [e.get("name"), e.get("difficulty", -1)])))
	# the lobby: TEAM menu sets the host's wish (a fresh host session: no peers yet)
	Game.mp_lobby = {"peers": {}}
	var l: Node = load("res://scenes/ui/Lobby.tscn").instantiate()
	add_child(l)
	for i in 3:
		await get_tree().process_frame
	var opt := l.find_child("TeamPick", true, false) as OptionButton
	if opt == null or l.find_child("BotSlotsBtn", true, false) == null:
		bad.append("the lobby has no TEAM menu / BOT SLOTS button")
	else:
		opt.select(2)
		opt.item_selected.emit(2)
		var me := multiplayer.get_unique_id()
		if int(Game.mp_lobby["peers"].get(me, {}).get("team_pref", -1)) != 1:
			bad.append("TEAM: B left the host's wish at %s" % str(Game.mp_lobby["peers"].get(me, {}).get("team_pref")))
		(l.find_child("BotSlotsBtn", true, false) as Button).pressed.emit()
		await get_tree().process_frame
		if l.find_child("Diff_1_0", true, false) == null:
			bad.append("BOT SLOTS shows no slot rows")
	if not bad.is_empty():
		_fail("; ".join(bad))
		return
	print("[probe] lobby_teams done")
	get_tree().quit(0)
