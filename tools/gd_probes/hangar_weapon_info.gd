extends Node
# T283 + T308 probe (user 2026-11-05: weapon range "in a drop-down mouseover menu", not the
# name; mech stats "partially occluded by the mech visual, fix that by using more of the space
# under the weapon picker"; T336 "Make the box background opaque"): every weapon in the hangar
# picker has an "i" (T466; was a hover tooltip) that opens, on an opaque box, its
# range; for every roster mech the
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
			# T466: the numbers sit behind the row's "i" (was a hover tooltip), on an opaque box
			var info: Button = lbl.get_parent().get_node_or_null("Info")
			var tip: String = String(info.get_meta("info", "")) if info != null else ""
			if not tip.contains("RANGE") or not tip.contains(" m"):
				_fail("%s: weapon %s has no range info (info '%s')" % [path.get_file(), (lbl as Label).text, tip])
				bad = true
				continue
			info.pressed.emit()
			var ib: PanelContainer = h.get("_info_box")
			var box = ib.get_theme_stylebox("panel") if ib != null else null  # T336: opaque box
			if not (box is StyleBoxFlat) or (box as StyleBoxFlat).bg_color.a < 1.0:
				_fail("%s: the weapon info box isn't opaque (%s)" % [path.get_file(), box])
				bad = true
			elif (ib.get_child(0) as Label).text != tip or not ib.visible:
				_fail("%s: weapon %s's info button doesn't open its info" % [path.get_file(), (lbl as Label).text])
				bad = true
			ib.visible = false
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
