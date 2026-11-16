extends Node
# T218 probe (HUMAN_FOUND_ISSUES: "Everest sometimes shows the old blue shield under the
# current textured one -- before taking damage?"): a spawned Everest's physical shield is
# up (collides), but its pre-kit placeholder mesh draws nothing; the kit model is the look.
# T242: and that kit shield disappears when the shield breaks.

func _fail(msg: String) -> void:
	push_error("[probe] everest_shield: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["squad"] = ["res://resources/mechs/Everest.tres"]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var m: Node = arena.get("player_mech")
	var shield: Node3D = m.get_node("Torso/PhysicalShield")
	if not shield.visible or (shield.get_node("CollisionShape3D") as CollisionShape3D).disabled:
		_fail("Everest's physical shield is not up at spawn")
	var old := shield.get_node_or_null("ShieldMesh") as MeshInstance3D
	if old != null and old.mesh != null and old.is_visible_in_tree():
		_fail("the old blue placeholder shield still draws under the kit model")
	# T242: the kit model's shield (slab + cross) draws while the shield is up and is gone
	# once it breaks; the rest of Everest still draws
	var kit_parts := shield.find_children("*", "MeshInstance3D", true, false).filter(
		func(n): return n.name != "ShieldMesh" and (n as MeshInstance3D).mesh != null)
	if kit_parts.size() < 3:
		_fail("only %d kit shield parts ride the physical shield (want the slab, face and cross)" % kit_parts.size())
	var torso: Node3D = m.get("torso")
	# T427: the body's boxes are merged per material, so count drawn triangles (a box = 12), not nodes
	var body_tris := func() -> int:
		var t := 0
		for n in torso.find_children("*", "MeshInstance3D", false, false):
			if (n as MeshInstance3D).mesh != null and (n as Node3D).is_visible_in_tree():
				t += (n as MeshInstance3D).mesh.get_faces().size() / 3
		return t
	var body_before: int = body_tris.call()
	shield.call("take_damage", 1.0e6)
	await get_tree().process_frame
	for n in kit_parts:
		if (n as Node3D).is_visible_in_tree():
			_fail("kit shield part %s still draws after the shield broke" % n.name)
			break
	var body_after: int = body_tris.call()
	if body_after < body_before or body_after < 10 * 12:  # still at least ten boxes' worth
		_fail("Everest's body lost meshes when the shield broke (%d -> %d triangles)" % [body_before, body_after])
	print("[probe] everest_shield done (%d kit shield parts)" % kit_parts.size())
	get_tree().quit(0)
