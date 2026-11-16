extends Node
# T253 probe (HUMAN_FOUND_ISSUES 2026-11-05: graphics toggles get a dedicated Settings
# page): Settings has a GRAPHICS button next to CONTROLS that opens GraphicsPage (with the
# FANCY HANGAR toggle). T315 (user: remove the FULL shadows option): no SHADOWS section
# on either page any more -- blob shadows are the only mode.

func _fail(msg: String) -> void:
	push_error("[probe] graphics_page: " + msg)

func _ready() -> void:
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	for l in st.find_children("*", "Label", true, false):
		if (l as Label).text == "SHADOWS":
			_fail("a SHADOWS section is still in Settings (T315 removed it)")
	if st.find_child("Shadow_full", true, false) != null:
		_fail("the FULL shadows button is still there")
	var open := st.find_child("GraphicsButton", true, false) as Button
	var page := st.find_child("GraphicsPage", true, false) as Control
	if open == null or page == null:
		_fail("no GRAPHICS button / page")
		get_tree().quit(0)
		return
	open.pressed.emit()
	await get_tree().process_frame
	if not page.visible or (st.get_node("Scroll") as Control).visible:
		_fail("GRAPHICS didn't open its page")
	if page.find_child("Fancy_on", true, false) == null:
		_fail("FANCY HANGAR toggle missing from the GRAPHICS page")
	# T428: RESOLUTION 50% -> the match's 3D view at half scale, back to full in the menus
	var half := page.find_child("Res_50", true, false) as Button
	if half == null or page.find_child("Res_100", true, false) == null:
		_fail("RESOLUTION 100 / 75 / 50 % buttons missing from the GRAPHICS page")
	else:
		var was = Game.settings.get("render_scale", 1.0)
		half.pressed.emit()
		if not is_equal_approx(float(Game.settings.get("render_scale", 1.0)), 0.5):
			_fail("RESOLUTION 50%% didn't set render_scale (%s)" % Game.settings.get("render_scale"))
		st.queue_free()
		Game.setup_sp_match()
		var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
		get_tree().root.add_child(arena)
		await get_tree().process_frame
		if not is_equal_approx(get_viewport().scaling_3d_scale, 0.5):
			_fail("the match draws its 3D view at %.2f, not 0.5" % get_viewport().scaling_3d_scale)
		arena.queue_free()
		await get_tree().process_frame
		if not is_equal_approx(get_viewport().scaling_3d_scale, 1.0):
			_fail("the 3D view stays at %.2f after the match (menus / hangar should be full)" % get_viewport().scaling_3d_scale)
		Game.settings["render_scale"] = was
		Game.save_settings()
	print("[probe] graphics_page done")
	get_tree().quit(0)
