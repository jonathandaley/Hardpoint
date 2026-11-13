extends Node
# T410 probe (HUMAN_FOUND, queued 2026-11-13: "\"Select spawn point\" should be more visible, a
# different color, bigger across the top when picking mechs in a match"): while the spawn picker is
# open, SELECT SPAWN POINT is a banner across the top of the screen -- big, coloured, not the
# minimap's small white corner label -- and it goes with the picker.

func _fail(msg: String) -> void:
	push_error("[probe] spawn_banner FAIL: " + msg)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 3:
		await get_tree().process_frame
	var hud: Node = arena.get("hud")
	if not arena.get("_start_pick_open"):
		_fail("no start pick to test with")
	hud.squad_slot_selected.emit(0)
	for i in 2:
		await get_tree().process_frame
	var banner: Label = null
	for l in hud.find_children("*", "Label", true, false):
		if (l as Label).text == "SELECT SPAWN POINT" and (l as Label).is_visible_in_tree():
			banner = l
	var view := get_viewport().get_visible_rect().size
	if banner == null:
		_fail("no SELECT SPAWN POINT shown")
	else:
		var r := banner.get_global_rect()
		var font := banner.get_theme_font_size("font_size")
		var col := banner.get_theme_color("font_color")
		if r.position.y > view.y * 0.2 or r.size.x < view.x * 0.5:
			_fail("not a banner across the top: %s in %s" % [r, view])
		if font < 20:
			_fail("font %d px (want big: 20+)" % font)
		if col.is_equal_approx(Color.WHITE) or (col.r > 0.9 and col.g > 0.9 and col.b > 0.9):
			_fail("still white (%s)" % col)
	hud.spawn_selected.emit(0)
	for i in 3:
		await get_tree().process_frame
	if banner != null and is_instance_valid(banner) and banner.is_visible_in_tree():
		_fail("the banner stayed after the pick")
	print("[probe] spawn_banner done")
	get_tree().quit(0)
