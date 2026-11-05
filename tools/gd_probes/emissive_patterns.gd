extends Node
# T255 probe (HUMAN_FOUND_ISSUES 2026-11-05: patterned emissives on the mech textures,
# behind a GRAPHICS toggle): with EMISSIVE PATTERNS on, a glowing mech's (Everest) armor
# material carries an emission pattern in its emissive colour; with it off it doesn't; a
# mech without an emissive (Cesh) stays dark either way; the toggle is on the GRAPHICS page.

func _fail(msg: String) -> void:
	push_error("[probe] emissive_patterns: " + msg)

func _armor(mech_name: String, on: bool) -> StandardMaterial3D:
	Game.settings["emissive_patterns"] = on
	var md: Resource = load("res://resources/mechs/%s.tres" % mech_name)
	var m: Node3D = md.scene.instantiate()
	MechVisuals.apply(m, mech_name)
	add_child(m)
	var found: StandardMaterial3D = null
	for mi in m.get_node("Torso").find_children("*", "MeshInstance3D", false, false):
		var mat := (mi as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		if mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path.ends_with("-armor.png"):
			found = mat
			break
	m.queue_free()
	return found

func _ready() -> void:
	var ev := _armor("Everest", true)
	if ev == null or not ev.emission_enabled or ev.emission_texture == null:
		_fail("Everest armor has no emission pattern with the setting on")
	var ev_off := _armor("Everest", false)
	if ev_off == null or ev_off.emission_enabled:
		_fail("Everest armor still glows with the setting off")
	var cesh := _armor("Cesh", true)
	if cesh == null or cesh.emission_enabled:
		_fail("Cesh (no emissive) got a glow pattern")
	Game.settings["emissive_patterns"] = true
	var st: Node = load("res://scenes/ui/Settings.tscn").instantiate()
	add_child(st)
	await get_tree().process_frame
	var b := st.find_child("Emissive_off", true, false) as Button
	if b == null or not st.find_child("GraphicsPage", true, false).is_ancestor_of(b):
		_fail("no EMISSIVE PATTERNS toggle on the GRAPHICS page")
	print("[probe] emissive_patterns done")
	get_tree().quit(0)
