extends Node
# T424 probe: MapScene.merge_static_meshes (skipped in headless runs, so called here) folds each
# map's plain static meshes into a few draws: collision is untouched (same shapes), fog curtains
# and other excluded meshes survive, merged meshes are opaque StandardMaterial3D, Badlands (611
# separate rocks before) ends up under 120 drawn surfaces.

func _fail(msg: String) -> void:
	push_error("[probe] map_merge: " + msg)

func _surfaces(map: Node) -> int:
	var n := 0
	for mi in map.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			n += (mi as MeshInstance3D).mesh.get_surface_count()
	return n

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var summary: Array = []
	for f in DirAccess.get_files_at("res://resources/maps"):
		if not f.ends_with(".tres"):
			continue
		Game.mp_active_match["roster"] = []
		Game.loadout["team_size"] = 1
		Game.loadout["map_def"] = load("res://resources/maps/" + f)
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child.call_deferred(arena)
		for i in 3:
			await get_tree().process_frame
		var map: Node = arena.get("_map")
		var name := f.get_basename()
		var shapes := map.find_children("*", "CollisionShape3D", true, false).size()
		var fog := map.find_children("FogEdge_*", "MeshInstance3D", false, false).size()
		var before := _surfaces(map)
		map.merge_static_meshes()
		var after := _surfaces(map)
		if map.find_children("*", "CollisionShape3D", true, false).size() != shapes:
			_fail("%s: collision shapes changed" % name)
		if map.find_children("FogEdge_*", "MeshInstance3D", false, false).size() != fog:
			_fail("%s: fog curtains were merged away" % name)
		if int(map.get("merged_count")) == 0 or after >= before:
			_fail("%s: nothing merged (%d -> %d surfaces)" % [name, before, after])
		for mi in map.find_children("Merged*", "MeshInstance3D", false, false):
			var m := (mi as MeshInstance3D).material_override as StandardMaterial3D
			if m == null or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				_fail("%s: a merged mesh draws with a see-through / non-standard material" % name)
		if name == "Badlands" and after > 120:
			_fail("Badlands still draws %d surfaces (648 before T424)" % after)
		summary.append("%s %d->%d" % [name, before, after])
		arena.queue_free()
		for i in 3:
			await get_tree().process_frame
	print("[probe] map_merge done (%s)" % ", ".join(summary))
	get_tree().quit(0)
