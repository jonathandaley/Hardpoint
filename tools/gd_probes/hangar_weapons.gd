extends Node
# T188 probe (HUMAN_FOUND_ISSUES: "mechs should show their equipped weapons in the hangar"):
# every squad lineup mech carries its slots' weapons, and the detail diorama mech re-arms
# when a weapon is cycled (it shows the saved pick, not the default).

const WeaponVisuals := preload("res://scripts/WeaponVisuals.gd")

func _fail(msg: String) -> void:
	push_error("[probe] hangar_weapons: " + msg)

func _weapon_paths(m: Node) -> Array:
	var out: Array = []
	for hp in m.get("torso").get_children():
		if hp.name.begins_with("Hardpoint") and not hp.is_queued_for_deletion() and hp.get_child_count() > 0:
			out.append(hp.get_child(0).scene_file_path)
	return out

func _ready() -> void:
	var h: Node = load("res://scenes/ui/Hangar.tscn").instantiate()
	get_tree().root.add_child.call_deferred(h)
	for i in 3:
		await get_tree().process_frame
	var armed := 0
	for m in h.get("_squad_nodes"):
		if m == null:
			continue
		if _weapon_paths(m).is_empty():
			_fail("lineup mech %s shows no weapons" % m.name)
		else:
			armed += 1
	h._on_slot_btn_pressed(0)
	await get_tree().process_frame
	var md: Resource = Game.loadout["mech_def"]
	var before: Array = _weapon_paths(h.get("_diorama_mech_node"))
	h._on_weapon_cycle(0, 1)  # the slot-1 '>' button
	await get_tree().process_frame
	var after: Array = _weapon_paths(h.get("_diorama_mech_node"))
	var saved: Array = Game.loadout.get("mech_weapon_choices", {}).get(md.resource_path, [])
	if after.is_empty() or saved.is_empty() or after[0] != saved[0]:
		_fail("diorama mech shows %s, saved pick is %s" % [after, saved])
	elif before.size() > 0 and after[0] == before[0]:
		_fail("cycling slot 1 did not change the shown weapon (%s)" % after[0])
	# T191: Seeker's weapon renders at its MechDef.weapon_scale (oversized on purpose)
	var sk: Resource = load("res://resources/mechs/Seeker.tres")
	var m: Node = sk.scene.instantiate()
	MechVisuals.apply(m, "Seeker")
	add_child(m)
	h._arm_display(m, sk)
	var w: Node = m.get("torso").get_node("Hardpoint0").get_child(0)
	var seeker_len := 0.0
	for mi in w.get_children():
		if mi is MeshInstance3D:
			seeker_len = maxf(seeker_len, (mi as MeshInstance3D).get_aabb().size.z)
	var normal_len := 0.0
	for part in WeaponVisuals._parts(WeaponVisuals.kit_name(w.scene_file_path), WeaponVisuals.HEAVY_SCALE):
		normal_len = maxf(normal_len, (part[0] as Mesh).get_aabb().size.z)
	if sk.weapon_scale < 1.5 or seeker_len < normal_len * sk.weapon_scale * 0.95:
		_fail("Seeker weapon %.2f m long, a normal heavy one %.2f m (weapon_scale %.1f)" % [seeker_len, normal_len, sk.weapon_scale])
	print("[probe] hangar_weapons done (armed lineup mechs %d, Seeker weapon %.2f m vs %.2f m, slot 1: %s -> %s)" % [
		armed, seeker_len, normal_len, before[0].get_file() if before.size() > 0 else "-", after[0].get_file() if after.size() > 0 else "-"])
	get_tree().quit(0)
