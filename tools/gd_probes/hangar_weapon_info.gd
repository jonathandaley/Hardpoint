extends Node
# T283 + T308 probe (user 2026-11-05: weapon range "in a drop-down mouseover menu", not the
# name; mech stats "partially occluded by the mech visual, fix that by using more of the space
# under the weapon picker"; T336 "Make the box background opaque"): every weapon in the hangar
# picker has a hover tooltip (on an opaque box) with its
# range (and the label takes the mouse, so the tooltip can show); for every roster mech the
# stats text sits under the picker and every line fits inside the picker's width.

func _fail(msg: String) -> void:
	push_error("[probe] hangar_weapon_info FAIL: " + msg)

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	var bad := false
	var roster: Array = h.get_script().get_script_constant_map()["ROSTER"]
	var stats: Label = h.get("mech_stats_label")
	for path in roster:
		Game.loadout["mech_def"] = load(path)
		h.call("_update_mech_panel")
		await get_tree().process_frame
		var picker: Control = h.find_child("WeaponPicker", true, false)
		if picker == null:
			_fail("%s: no weapon picker" % path.get_file())
			bad = true
			continue
		for lbl in picker.find_children("Weapon", "Label", true, false):
			var tip: String = (lbl as Label).tooltip_text
			var box = (lbl as Label).get_theme_stylebox("panel", "TooltipPanel")  # T336: opaque box
			if not (box is StyleBoxFlat) or (box as StyleBoxFlat).bg_color.a < 1.0:
				_fail("%s: the weapon tooltip box isn't opaque (%s)" % [path.get_file(), box])
				bad = true
			if not tip.contains("RANGE") or not tip.contains(" m") or (lbl as Label).mouse_filter == Control.MOUSE_FILTER_IGNORE:
				_fail("%s: weapon %s has no range tooltip (tip '%s', mouse_filter %d)" % [path.get_file(), (lbl as Label).text, tip, (lbl as Label).mouse_filter])
				bad = true
		var pr := picker.get_global_rect()
		var sr := stats.get_global_rect()
		var font := stats.get_theme_font("font")
		var fs := stats.get_theme_font_size("font_size")
		for line in stats.text.split("\n"):
			var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if sr.position.x + w > pr.end.x + 1.0:
				_fail("%s: stats line '%s' runs %.0f px past the picker into the preview" % [path.get_file(), line, sr.position.x + w - pr.end.x])
				bad = true
		if sr.position.y < pr.end.y - 1.0:
			_fail("%s: stats overlap the picker" % path.get_file())
			bad = true
	if bad:
		get_tree().quit(1)
		return
	print("[probe] hangar_weapon_info done (%d mechs)" % roster.size())
	get_tree().quit(0)
