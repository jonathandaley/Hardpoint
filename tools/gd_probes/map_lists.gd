extends Node
# T248 probe (user 2026-11-05: "Delete ironworks, was a placeholder"): the Hangar (SP
# picker) and Lobby map lists name the same maps, every one loads and has its own scene,
# and Ironworks is gone. (A saved loadout naming a deleted map falls back to the default:
# Game checks ResourceLoader.exists before load.)

func _fail(msg: String) -> void:
	push_error("[probe] map_lists: " + msg)

func _ready() -> void:
	var hangar: Array = load("res://scripts/Hangar.gd").get_script_constant_map()["MAPS"]
	var lobby: Array = load("res://scripts/Lobby.gd").get_script_constant_map()["_MAP_OPTIONS"].map(func(o): return o["path"])
	var a := hangar.duplicate()
	var b := lobby.duplicate()
	a.sort()
	b.sort()
	if a != b:
		_fail("Hangar and Lobby list different maps: %s vs %s" % [a, b])
	for path in hangar:
		if String(path).contains("Ironworks"):
			_fail("Ironworks is still listed")
		var md: Resource = load(path) if ResourceLoader.exists(path) else null
		if md == null or String(md.get("scene_path")) == "":
			_fail("%s: missing or has no scene of its own" % path)
	if ResourceLoader.exists("res://resources/maps/Ironworks.tres"):
		_fail("resources/maps/Ironworks.tres still exists")
	print("[probe] map_lists done (%d maps)" % hangar.size())
	get_tree().quit(0)
