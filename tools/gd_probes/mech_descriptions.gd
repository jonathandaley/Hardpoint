extends Node
# T406 probe (HUMAN_FOUND, queued 2026-11-13: "Improve mech descriptions: they currently barely
# mention shields, and don't mention abilities at all. Also add some lore ... Do a similar thing for
# the weapons."): every roster mech's description names its shield (physical / energy) and its
# ability with the key that fires it; the hangar shows it from an info button after the mech name; every weapon's hangar
# tooltip carries a description line under the numbers.

const Lobby := preload("res://scripts/Lobby.gd")

func _fail(msg: String) -> void:
	push_error("[probe] mech_descriptions FAIL: " + msg)

func _ready() -> void:
	var bad: Array = []
	for path in Lobby.ROSTER:
		var md: Resource = load(path)
		var d: String = String(md.description)
		var name: String = md.display_name
		if md.has_shields and not d.to_lower().contains("physical shield"):
			bad.append("%s: no physical shield in '%s'" % [name, d])
		if md.has_energy_shield and not d.to_upper().contains("ENERGY SHIELD"):
			bad.append("%s: no energy shield in '%s'" % [name, d])
		for a in md.abilities:
			if not d.contains(String(a.ability_name)) or (a.trigger == 0 and not d.contains("SPACE")):
				bad.append("%s: ability %s not described with its key" % [name, a.ability_name])
		if d.count(". ") + d.count(".\n") < 1 or d.length() < 120:
			bad.append("%s: one short line, no lore (%d chars)" % [name, d.length()])
	var Hangar: Script = load("res://scripts/Hangar.gd")
	for i in Lobby.WEAPON_CATALOG.size():
		var tip: String = Hangar.call("weapon_tip", i)
		var parts := tip.split("\n\n")
		if parts.size() < 2 or parts[1].length() < 30:
			bad.append("%s: tooltip has no description (%s)" % [Lobby.WEAPON_CATALOG[i]["name"], tip.replace("\n", " | ")])
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	h.call("_show_detail_screen", 0)
	await get_tree().process_frame
	var lbl := h.get("mech_name_label") as Label
	var md0: Resource = Game.loadout.get("mech_def")
	# T466: a click on the "i" after the name opens the description; the next click closes it
	var btn: Button = lbl.get_node_or_null("MechInfo") if lbl != null else null
	if btn == null or md0 == null:
		bad.append("the hangar's mech name has no info button")
	else:
		btn.pressed.emit()
		await get_tree().process_frame
		var box: Control = h.get("_info_box")
		if box == null or not box.is_visible_in_tree() or h.call("info_box_text") != String(md0.description):
			bad.append("the info button doesn't open the description")
		else:
			var f := lbl.get_theme_font("font")
			var w := f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lbl.get_theme_font_size("font_size")).x
			if btn.get_global_rect().position.x < lbl.global_position.x + w:
				bad.append("the info button sits on the mech name")
			if box.get_global_rect().end.x > 640.0:
				bad.append("the description box runs off screen")
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			h.call("_input", ev)
			if box.visible:
				bad.append("a click elsewhere doesn't close the description")
	if not bad.is_empty():
		_fail("; ".join(bad))
	print("[probe] mech_descriptions done")
	get_tree().quit(0)
