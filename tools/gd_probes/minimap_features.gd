extends Node
# T239 probe (HUMAN_FOUND_ISSUES 2026-11-04: "add some minimal terrain features to the
# minimap"): the minimap carries footprints of the map's solid geometry -- on Sydney a city
# block shows and a street doesn't; on Corvette a wall block shows and the reactor room
# (open floor under the ceiling) doesn't -- and no footprint covers the whole map.

func _fail(msg: String) -> void:
	push_error("[probe] minimap_features: " + msg)

func _covered(feats: Array, p: Vector2) -> bool:
	for f in feats:
		if Geometry2D.is_point_in_polygon(p, f):
			return true
	return false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var counts := []
	for c in [["res://resources/maps/City.tres", Vector2(28, 6), Vector2(52, 6)],
			["res://resources/maps/Corvette.tres", Vector2(0, 28.5), Vector2(0, 0)]]:  # T303: the hull block was at 40.75 (x 0.7)
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["map_def"] = load(c[0])
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 3:
			await get_tree().process_frame
		var mm: Node = arena.get("hud").get("minimap")
		var got = mm.get("features") if mm != null else null
		var feats: Array = got if got is Array else []
		var name := String(c[0]).get_file().get_basename()
		if feats.size() < 10:
			_fail("%s: %d minimap features" % [name, feats.size()])
		if not _covered(feats, c[1]):
			_fail("%s: nothing drawn at the solid %s" % [name, c[1]])
		if _covered(feats, c[2]):
			_fail("%s: open ground %s is drawn as solid" % [name, c[2]])
		counts.append("%s %d" % [name, feats.size()])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] minimap_features done (%s)" % ", ".join(counts))
	get_tree().quit(0)
