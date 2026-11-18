extends Node
# T477 probe (HUMAN_FOUND 2026-11-18, with T467: "Team selection, hangar selection, etc"): the lobby's
# HANGAR menu lists the hangar's saved squads; picking one makes it the squad -- in the loadout and in
# our lobby entry (host side), weapons included; with no presets the menu is off.

func _fail(msg: String) -> void:
	push_error("[probe] lobby_hangar FAIL: " + msg)
	get_tree().quit(1)

func _ready() -> void:
	var lobby_script: Script = load("res://scripts/Lobby.gd")
	var roster: Array = lobby_script.get_script_constant_map()["ROSTER"]
	var squad: Array = []
	for i in 5:
		squad.append(roster[(i + 2) % roster.size()])
	Game.loadout["squad"] = roster.slice(0, 5)
	Game.loadout["presets"] = {"Zeta": {"squad": squad, "weapons": {}, "slot_weapons": []}, "Alpha": {"squad": roster.slice(0, 5), "weapons": {}, "slot_weapons": []}}
	var l: Node = load("res://scenes/ui/Lobby.tscn").instantiate()
	add_child(l)
	for i in 3:
		await get_tree().process_frame
	var opt := l.find_child("HangarPick", true, false) as OptionButton
	if opt == null:
		_fail("the lobby has no HANGAR menu")
		return
	var texts: Array = []
	for i in opt.item_count:
		texts.append(opt.get_item_text(i))
	if texts != ["HANGAR: CURRENT", "HANGAR: ALPHA", "HANGAR: ZETA"] or opt.disabled:
		_fail("the menu lists %s (disabled %s)" % [str(texts), opt.disabled])
		return
	opt.select(2)
	opt.item_selected.emit(2)
	await get_tree().process_frame
	if Game.loadout["squad"] != squad:
		_fail("picking ZETA left the loadout squad at %s" % str(Game.loadout["squad"]))
		return
	var me := multiplayer.get_unique_id()
	var entry: Array = Game.mp_lobby["peers"].get(me, {}).get("squad", [])
	if entry.map(func(e): return e.get("mech")) != squad:
		_fail("our lobby entry has %s, want ZETA's squad" % str(entry.map(func(e): return e.get("mech"))))
		return
	l.queue_free()
	await get_tree().process_frame
	Game.loadout["presets"] = {}
	var l2: Node = load("res://scenes/ui/Lobby.tscn").instantiate()
	add_child(l2)
	await get_tree().process_frame
	if not (l2.find_child("HangarPick", true, false) as OptionButton).disabled:
		_fail("with no saved squads the HANGAR menu is live")
		return
	print("[probe] lobby_hangar done")
	get_tree().quit(0)
