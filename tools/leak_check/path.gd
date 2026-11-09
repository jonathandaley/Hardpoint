extends Node
# T346 (HUMAN_FOUND 2026-11-08: 4 textures of 349524 bytes leaked at exit after playing Factory --
# T320 only checked quitting straight out of one match): walks the user's real path with real GL
# (run under Xvfb, not headless: headless has no GL to leak) -- hangar, then each map in the list
# as a single-player match for a few seconds, back to the hangar between them, then quit like a
# window close. The engine prints "leaked" lines at exit if a texture outlives the scene.
#   xvfb-run -a -s "-screen 0 1280x720x24" ~/bin/godot --resolution 1280x720 res://tools/leak_check/path.tscn -- Factory,Factory
const MATCH_S := 4.0

var driver := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not driver:  # we're the scene: changing scenes would free us -- run from a node under root
		var d := Node.new()
		d.set_script(get_script())
		d.set("driver", true)
		get_tree().root.add_child.call_deferred(d)
		return
	var args := OS.get_cmdline_user_args()
	var maps: Array = Array(args[0].split(",")) if args.size() > 0 else ["Factory"]
	await _scene("res://scenes/ui/Hangar.tscn", 1.0)
	for m in maps:
		Game.loadout["map_def"] = load("res://resources/maps/%s.tres" % m)
		Game.loadout["team_size"] = 2
		Game.mp_active_match["roster"] = []
		Game.setup_sp_match()
		await _scene("res://scenes/arena/Arena.tscn", MATCH_S)
		var arena := get_tree().current_scene
		if arena != null and arena.get("_start_pick_open"):
			arena.get("hud").squad_slot_selected.emit(0)
			arena.get("hud").spawn_selected.emit(0)
		await get_tree().create_timer(MATCH_S, true).timeout
		Game.disconnect_mp() if Game.has_method("disconnect_mp") else null
		await _scene("res://scenes/ui/Hangar.tscn", 1.0)
	print("[leak_check] path done: hangar -> %s -> hangar" % " -> hangar -> ".join(maps))
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit(0)

func _scene(path: String, settle: float) -> void:
	get_tree().change_scene_to_file(path)
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(settle, true).timeout
