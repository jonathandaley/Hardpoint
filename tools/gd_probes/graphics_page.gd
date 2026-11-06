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
	print("[probe] graphics_page done")
	get_tree().quit(0)
