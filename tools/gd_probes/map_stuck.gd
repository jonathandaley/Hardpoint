extends Node
# T221 probe: every map scene (one per distinct MapDef.scene_path in resources/maps) passes
# tools/maps/stuck_check.gd: every spawn reaches every beacon on the navmesh, and no
# walk-out grid point (every SPACING m) wedges a mech. Navmesh islands are counted, not failed.

const SPACING := 20.0
const Check := preload("res://tools/maps/stuck_check.gd")

func _fail(msg: String) -> void:
	push_error("[probe] map_stuck: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenes := {}
	for f in DirAccess.get_files_at("res://resources/maps"):
		if f.ends_with(".tres"):
			var md: Resource = load("res://resources/maps/" + f)
			if not scenes.has(md.scene_path):
				scenes[md.scene_path] = md
	var summary: Array = []
	for sp in scenes:
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["map_def"] = scenes[sp]
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 2:
			await get_tree().process_frame
		if arena.get("_start_pick_open"):
			arena.get("hud").squad_slot_selected.emit(0)
			arena.get("hud").spawn_selected.emit(0)
		for t in 2:  # the match's own mechs out of the way: parked, untargetable
			for m in arena.get("_team_mechs")[t]:
				m.invincible = true
				m.process_mode = Node.PROCESS_MODE_DISABLED
		var r: Dictionary = await Check.run(arena, SPACING)
		r["map"] = String(sp).get_file().get_basename()  # one scene, maybe several MapDefs
		for u in r["unreached"]:
			_fail("%s: no nav path %s" % [r["map"], u])
		for s in r["stuck"]:
			_fail("%s: a mech is stuck at %s" % [r["map"], s])
		summary.append("%s %d points, %d stuck, %d unreached, %d island points (look: tools/maps/stuck_check.tscn)" % [
			r["map"], r["tested"], r["stuck"].size(), r["unreached"].size(), r["islands"].size()])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] map_stuck done (%s)" % "; ".join(summary))
	get_tree().quit(0)
