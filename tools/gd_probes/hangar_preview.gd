extends Node
# T409 probe (HUMAN_FOUND, queued 2026-11-13: "Change mech preview in hangar to a drag-and-spin if
# that's easy. Arrow buttons to rotate it 45 degrees would also be fine and probably easier.
# Stationary 3/4 default view."): the detail preview holds still at the lineup's 3/4 view, the arrow
# buttons turn it 45 degrees, and dragging across it spins it.

func _fail(msg: String) -> void:
	push_error("[probe] hangar_preview FAIL: " + msg)

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_show_detail_screen", 0)
	for i in 2:
		await get_tree().process_frame
	var spin: Node3D = h.get("_diorama_spin")
	var yaw0 := spin.rotation.y
	for i in 30:
		await get_tree().process_frame
	if absf(spin.rotation.y - yaw0) > 0.001:
		_fail("the preview turns on its own (%.2f -> %.2f rad)" % [yaw0, spin.rotation.y])
	var want := deg_to_rad(float(h.get_script().get_script_constant_map().get("LINEUP_YAW", 0.0)))
	if absf(angle_difference(yaw0, want)) > 0.01:
		_fail("default view %.2f rad, want the lineup's 3/4 view %.2f" % [yaw0, want])
	var right := h.find_child("PreviewRight", true, false) as Button
	var left := h.find_child("PreviewLeft", true, false) as Button
	if right == null or left == null:
		_fail("no rotate buttons")
	else:
		right.pressed.emit()
		for i in 30:
			await get_tree().process_frame
		if absf(angle_difference(spin.rotation.y, yaw0 + PI / 4.0)) > 0.01:
			_fail("> turned it to %.2f rad, want +45 deg (%.2f)" % [spin.rotation.y, yaw0 + PI / 4.0])
		left.pressed.emit()
		left.pressed.emit()
		for i in 30:
			await get_tree().process_frame
		if absf(angle_difference(spin.rotation.y, yaw0 - PI / 4.0)) > 0.01:
			_fail("< < turned it to %.2f rad, want -45 deg from the start" % spin.rotation.y)
	var box := h.get("_diorama_container") as Control
	var before := spin.rotation.y
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	box.gui_input.emit(down)
	var mv := InputEventMouseMotion.new()
	mv.relative = Vector2(60, 0)
	mv.button_mask = MOUSE_BUTTON_MASK_LEFT
	box.gui_input.emit(mv)
	await get_tree().process_frame
	if absf(spin.rotation.y - before) < 0.2:
		_fail("dragging across the preview didn't spin it")
	print("[probe] hangar_preview done")
	get_tree().quit(0)
