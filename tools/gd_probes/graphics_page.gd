extends Node
# T253 probe (HUMAN_FOUND_ISSUES 2026-11-05: graphics toggles get a dedicated Settings
# page): Settings has a GRAPHICS button next to CONTROLS; it opens GraphicsPage with the
# SHADOWS buttons (moved off the main page), and they still change the setting.

func _fail(msg: String) -> void:
	push_error("[probe] graphics_page: " + msg)

func _ready() -> void:
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	var main: Node = st.get_node("Scroll/Content")
	for l in main.find_children("*", "Label", true, false):
		if (l as Label).text == "SHADOWS":
			_fail("SHADOWS is still on the main settings page")
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
	var full := page.find_child("Shadow_full", true, false) as Button
	if full == null:
		_fail("SHADOWS buttons are not on the GRAPHICS page")
	else:
		var before: String = Game.settings.get("shadows", "blob")
		full.pressed.emit()
		if Game.settings.get("shadows") != "full":
			_fail("SHADOW FULL on the GRAPHICS page didn't change the setting")
		Game.settings["shadows"] = before
	print("[probe] graphics_page done")
	get_tree().quit(0)
