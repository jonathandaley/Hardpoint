extends Node
# T406 probe (HUMAN_FOUND, queued 2026-11-13: "Improve mech descriptions: they currently barely
# mention shields, and don't mention abilities at all. Also add some lore ... Do a similar thing for
# the weapons."): every roster mech's description names its shield (physical / energy) and its
# ability with the key that fires it; the hangar shows it on the mech name; every weapon's hangar
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
	if lbl == null or md0 == null or lbl.tooltip_text != String(md0.description):
		bad.append("the hangar's mech name doesn't show the description on hover")
	if not bad.is_empty():
		_fail("; ".join(bad))
	print("[probe] mech_descriptions done")
	get_tree().quit(0)
