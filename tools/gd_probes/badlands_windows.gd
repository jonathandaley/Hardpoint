extends Node3D
# T288 probe (HUMAN_FOUND 2026-11-05: "Badlands should have some decrepit windows in the
# buildings"): the Badlands ruins cut window holes into a good share of their tall wall segments
# (sill, piers, lintel -- some lintels fallen), at least MIN_WINDOWS across the map; the map stays
# walkable (probe map_stuck).

const MIN_WINDOWS := 15

func _ready() -> void:
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	add_child(we)
	var md: Resource = load("res://resources/maps/Badlands.tres")
	var map: Node3D = (load(md.get("scene_path")) as PackedScene).instantiate()
	add_child(map)
	map.call("build")
	await get_tree().process_frame
	var n = map.get("window_count")
	if n == null or int(n) < MIN_WINDOWS:
		push_error("[probe] badlands_windows FAIL: %s window holes, want >= %d" % [str(n), MIN_WINDOWS])
		get_tree().quit(1)
		return
	print("[probe] badlands_windows done (%d windows)" % int(n))
	get_tree().quit(0)
