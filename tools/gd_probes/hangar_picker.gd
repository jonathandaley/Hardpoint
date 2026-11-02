extends Node
# T173 probe (HUMAN_FOUND_ISSUES): the hangar weapon picker must hide whenever the squad
# screen shows. Re-entering a slot or picking another mech rebuilt the picker in the same
# frame as the old one's queue_free -> the new one got an auto-name -> _show_squad_screen
# never found "WeaponPicker" to hide, and it overlapped the squad screen (and came back
# after pilot tab -> mech tab).

func _fail(msg: String) -> void:
	push_error("[probe] hangar_picker: " + msg)

func _pickers(h: Node) -> int:
	var n := 0
	for c in h.mech_panel.get_children():
		if c is VBoxContainer and c != h.get("_lineup_container") and c.visible and not c.is_queued_for_deletion():
			n += 1
	return n

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	await get_tree().process_frame
	await get_tree().process_frame
	# [slot to open, roster mech to pick there (-1 = none)]
	for step in [[0, -1], [1, -1], [0, 2]]:
		h._on_slot_btn_pressed(step[0])
		if step[1] >= 0:
			h._on_roster_selected(step[1])
		await get_tree().process_frame
		if _pickers(h) != 1:
			_fail("slot %d detail screen shows %d weapon pickers" % [step[0], _pickers(h)])
		h._on_back_pressed()
		await get_tree().process_frame
		if _pickers(h) != 0:
			_fail("squad screen still shows a weapon picker after slot %d" % step[0])
	h._on_pilot_tab_pressed()
	await get_tree().process_frame
	h._on_mech_tab_pressed()
	await get_tree().process_frame
	if _pickers(h) != 0:
		_fail("weapon picker back after pilot tab -> mech tab")
	print("[probe] hangar_picker done")
	get_tree().quit(0)
