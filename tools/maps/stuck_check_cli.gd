extends Node
# T221: one map, finer grid, every finding printed.
#   godot --headless --path . res://tools/maps/stuck_check.tscn -- map=res://resources/maps/Badlands.tres spacing=8
#   [mech=res://resources/mechs/Everest.tres]  (T230: default Hippogriff)
const Check := preload("res://tools/maps/stuck_check.gd")

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var arg := {"map": "res://resources/maps/MathTemple.tres", "spacing": "10"}
	for kv in OS.get_cmdline_user_args():
		var p: PackedStringArray = kv.split("=", true, 1)
		if p.size() == 2:
			arg[p[0]] = p[1]
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load(arg["map"])
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for t in 2:
		for m in arena.get("_team_mechs")[t]:
			m.invincible = true
			m.process_mode = Node.PROCESS_MODE_DISABLED
	var r: Dictionary = await Check.run(arena, float(arg["spacing"]), arg.get("mech", "res://resources/mechs/Hippogriff.tres"))
	print("[stuck_check] %s: %d points, %d stuck, %d unreached, %d island points" % [r["map"], r["tested"],
		r["stuck"].size(), r["unreached"].size(), r["islands"].size()])
	for k in ["unreached", "stuck", "islands"]:
		for v in r[k]:
			print("  %s %s" % [k, v])
	get_tree().quit(0)
