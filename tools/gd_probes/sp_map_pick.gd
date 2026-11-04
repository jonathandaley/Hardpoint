extends Node
# T228 probe (HUMAN_FOUND_ISSUES 2026-11-04: "map picker for singleplayer should be after
# choosing singleplayer, not buried in settings"): FIND MATCH -> SINGLE PLAYER shows one
# button per map (no match yet); picking one starts the SP match on that map and saves the
# choice (the next picker highlights it); Settings has no map section any more.

func _fail(msg: String) -> void:
	push_error("[probe] sp_map_pick: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	for c in st.find_children("*", "Label", true, false):
		if (c as Label).text.begins_with("MAP"):
			_fail("Settings still has a map section ('%s')" % (c as Label).text)
	st.queue_free()
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	get_tree().current_scene = h  # the SP start replaces the hangar, not this probe
	var maps: Array = h.get("MAPS")
	(h.get_node("MatchmakingButton") as Button).pressed.emit()
	(h.get_node("FindMatchPanel/Choices/SinglePlayerBtn") as Button).pressed.emit()
	await get_tree().process_frame
	if get_tree().current_scene != h:
		_fail("SINGLE PLAYER started a match before a map was picked")
		get_tree().quit(0)
		return
	var picker: Control = h.get_node_or_null("FindMatchPanel/MapChoices")
	if picker == null or not picker.is_visible_in_tree():
		_fail("no map picker after SINGLE PLAYER")
		get_tree().quit(0)
		return
	await get_tree().process_frame  # containers lay out
	var screen := Rect2(Vector2.ZERO, Vector2(640, 360))  # project viewport
	if not screen.encloses(picker.get_global_rect()):
		_fail("map picker %s runs off the 640x360 screen" % picker.get_global_rect())
	var btns: Array = picker.find_children("Map*", "Button", true, false)
	if btns.size() != maps.size():
		_fail("map picker has %d buttons, %d maps" % [btns.size(), maps.size()])
	var want := maps.find("res://resources/maps/Swamp.tres")
	(picker.find_child("Map%d" % want, true, false) as Button).pressed.emit()
	for i in 4:
		await get_tree().process_frame
	var arena: Node = get_tree().current_scene
	var map: Node = arena.get("_map") if arena != null else null
	if map == null or map.get_script().resource_path != "res://scripts/maps/Swamp.gd":
		_fail("picking Swamp started %s" % (map.get_script().resource_path if map != null else str(arena)))
	var md: Resource = Game.loadout.get("map_def")
	if md == null or md.resource_path != "res://resources/maps/Swamp.tres":
		_fail("the pick was not kept in the loadout (%s)" % md)
	print("[probe] sp_map_pick done (%d maps in the picker)" % btns.size())
	get_tree().quit(0)
