extends Node
# T345 probe (HUMAN_FOUND 2026-11-08: "two of the same mech in a squad can't carry different
# weapons -- changing one changes all"): with Pegasus in squad slots 0 and 1, picking a weapon in
# slot 1's detail screen leaves slot 0's alone; the match squad (Lobby._build_squad_data, also
# the in-match picker's cards), the hangar lineup, a save / reload and a preset all keep the two
# apart; a slot given a new mech starts from that mech's last picks.

func _fail(msg: String) -> void:
	push_error("[probe] squad_dupes FAIL: " + msg)
	get_tree().quit(1)

func _guns(m: Node) -> Array:
	return m.get_weapons().map(func(w): return String(w.scene_file_path).get_file())

func _ready() -> void:
	var peg := "res://resources/mechs/Pegasus.tres"
	Game.loadout["squad"] = [peg, peg, "res://resources/mechs/Everest.tres", "res://resources/mechs/Cesh.tres", "res://resources/mechs/Slip.tres"]
	Game.loadout["squad_weapons"] = []
	Game.loadout["mech_weapon_choices"] = {}
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_on_slot_btn_pressed", 1)
	h.call("_on_weapon_cycle", 0, 1)
	h.call("_on_weapon_cycle", 1, 1)
	h.call("_on_back_pressed")
	await get_tree().process_frame
	var w0: Array = Game.slot_weapons(0)
	var w1: Array = Game.slot_weapons(1)
	if w1.is_empty() or w0 == w1:
		_fail("slot 1's pick reached slot 0 too (%s / %s)" % [w0, w1])
		return
	var sq: Array = load("res://scripts/Lobby.gd")._build_squad_data()
	if sq[0]["weapons"] == sq[1]["weapons"]:
		_fail("the match squad sends both Pegasus the same weapons %s" % [sq[0]["weapons"]])
		return
	h.call("_refresh_lineup_mechs")
	await get_tree().process_frame
	var nodes: Array = h.get("_squad_nodes")
	if nodes.size() >= 2 and nodes[0] != null and nodes[1] != null and is_instance_valid(nodes[0]) and _guns(nodes[0]) == _guns(nodes[1]):
		_fail("the hangar lineup shows both Pegasus with %s" % [_guns(nodes[0])])
		return
	Game.save_loadout()
	Game.loadout["squad_weapons"] = []
	Game._load_loadout()
	if Game.slot_weapons(1) != w1 or Game.slot_weapons(0) == w1:
		_fail("per-slot picks didn't survive a save / reload (%s / %s)" % [Game.slot_weapons(0), Game.slot_weapons(1)])
		return
	Game.save_preset("Dupes")
	Game.loadout["squad_weapons"] = []
	Game.load_preset("Dupes")
	if Game.slot_weapons(1) != w1 or Game.slot_weapons(0) == w1:
		_fail("a preset lost the per-slot picks")
		return
	# a slot given another mech starts from that mech's own last picks
	var other := 0
	while String(h.get("_mechs")[other].resource_path) == peg:
		other += 1
	h.call("_on_slot_btn_pressed", 1)
	h.call("_on_roster_selected", other)
	var opath: String = h.get("_mechs")[other].resource_path
	if Game.slot_weapons(1) != Game.loadout["mech_weapon_choices"].get(opath, []):
		_fail("slot 1's new mech kept the old Pegasus picks %s" % [Game.slot_weapons(1)])
		return
	print("[probe] squad_dupes done (slot 0 %s, slot 1 %s)" % [w0, w1])
	get_tree().quit(0)
