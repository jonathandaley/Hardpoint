extends Node
# T346 probe (rendered: run_suite runs render_* probes under Xvfb with GL, not --headless): playing
# Factory and quitting straight from the match leaks no GL textures. Godot 4.6's compatibility
# renderer keeps a list of skies to (re)build radiance for and doesn't unlink a Sky freed from it:
# a Sky dropped in the frame it was loaded or changed gets two 256 px radiance maps allocated after
# its death, never freed ("Texture with GL ID of N: leaked 349524 bytes" at exit, crash_scan fails).
# Factory replaced the arena's freshly loaded Sky with its own before a frame drew.

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("[probe] render_sky_leak: needs a display (run_suite runs it under Xvfb)")
		get_tree().quit(1)
		return
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	for map in ["Giza", "Factory"]:  # every map with own_sky() (T453 Giza); the last stays up at quit
		Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % map)
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()  # a temporary PackedScene, as map_survey
		get_tree().root.add_child.call_deferred(arena)
		for i in 10:
			await get_tree().process_frame
		if map != "Factory":
			arena.queue_free()
			for i in 3:
				await get_tree().process_frame
	print("[probe] render_sky_leak: done (a leak shows as ERROR lines at exit)")
	get_tree().quit(0)
