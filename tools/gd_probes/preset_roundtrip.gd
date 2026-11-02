extends Node
# T177 probe: hangar squad presets (user 2026-11-02: whole squad, typed name, save /
# load / delete in the hangar, no slot limit, persisted with the profile). Drives the
# panel's own buttons: save the squad as "Alpha", change slot 0 + its weapons, load
# Alpha back, check it survives a reload from disk, delete it.

func _fail(msg: String) -> void:
	push_error("[probe] preset_roundtrip: " + msg)

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	add_child(h)
	await get_tree().process_frame
	var s0: Array = (Game.loadout["squad"] as Array).duplicate()
	var sniper := ["res://scenes/weapons/SniperLight.tscn"]
	Game.loadout["mech_weapon_choices"][s0[0]] = sniper.duplicate()

	h._on_presets_pressed()
	if not h.get_node("PresetPanel").visible or not h.get_node("PresetPanel/Box/Empty").visible:
		_fail("preset panel did not open empty")
	h.get_node("PresetPanel/Box/SaveRow/NameEdit").text = "Alpha"
	h.get_node("PresetPanel/Box/SaveRow/SaveBtn").pressed.emit()
	await get_tree().process_frame
	var row := h.get_node_or_null("PresetPanel/Box/Scroll/List/Preset0")
	if row == null or row.get_node("Name").text != "Alpha":
		_fail("saved preset not listed")
	h._on_preset_close_pressed()

	# change slot 0's mech and the old mech's weapons
	var other := 0
	while h._mechs[other].resource_path == s0[0]:
		other += 1
	h._on_slot_btn_pressed(0)
	h._on_roster_selected(other)
	h._on_back_pressed()
	Game.loadout["mech_weapon_choices"][s0[0]] = ["res://scenes/weapons/RifleLight.tscn"]
	if Game.loadout["squad"][0] == s0[0]:
		_fail("probe could not change slot 0")

	h._on_presets_pressed()
	await get_tree().process_frame
	h.get_node("PresetPanel/Box/Scroll/List/Preset0/Load").pressed.emit()
	await get_tree().process_frame
	if Game.loadout["squad"] != s0:
		_fail("load gave squad %s, saved %s" % [Game.loadout["squad"], s0])
	if Game.loadout["mech_weapon_choices"].get(s0[0]) != sniper:
		_fail("load did not restore slot 0's weapons")
	var md = load(s0[0])
	if h._slot_labels[0].text != md.display_name.to_upper():
		_fail("hangar lineup label shows %s after load" % h._slot_labels[0].text)
	if h.get_node("PresetPanel").visible:
		_fail("panel still open after load")

	# persisted with the profile
	Game.loadout["presets"] = {}
	Game._load_loadout()
	if not Game.loadout["presets"].has("Alpha") or Game.loadout["presets"]["Alpha"]["squad"] != s0:
		_fail("preset not persisted: %s" % [Game.loadout["presets"]])

	h._on_presets_pressed()
	await get_tree().process_frame
	h.get_node("PresetPanel/Box/Scroll/List/Preset0/Delete").pressed.emit()
	await get_tree().process_frame
	Game._load_loadout()
	if not Game.loadout["presets"].is_empty() or h.get_node_or_null("PresetPanel/Box/Scroll/List/Preset0") != null:
		_fail("delete left %s" % [Game.loadout["presets"].keys()])
	print("[probe] preset_roundtrip done")
	get_tree().quit(0)
