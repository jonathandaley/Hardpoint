extends Node
# T450 probe (user 2026-11-17: yes to "a plinth at the base and a team-coloured light at the top"):
# a beacon has a plinth at its foot and a lamp at the top of its beam whose colour follows the
# beacon's state (neutral / team A / team B / contested) through the existing visuals update.

func _fail(msg: String) -> void:
	push_error("[probe] beacon_look: " + msg)

func _ready() -> void:
	var b: Node3D = load("res://scenes/beacon/Beacon.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	var bad := 0
	var lamp: MeshInstance3D = null
	var plinth := false
	for c in b.get_node("Visual").get_children():
		if c is MeshInstance3D and c.mesh is SphereMesh and c.position.y > 20.0:
			lamp = c
		elif c is MeshInstance3D and c.mesh is CylinderMesh and c.position.y < 1.0:
			plinth = true
	if lamp == null or not plinth:
		bad += 1
		_fail("plinth %s, lamp %s" % [plinth, lamp])
	else:
		var seen := {}
		for st in [0, 1, 2, 3]:
			b.set("state", st)
			b.call("_update_visuals")
			var m := lamp.get_surface_override_material(0) as StandardMaterial3D
			seen[m.emission.to_html()] = st
		if seen.size() != 4:
			bad += 1
			_fail("the lamp shows %d colours over the 4 states, want 4" % seen.size())
	print("[probe] beacon_look: %s" % ("PASS" if bad == 0 else "FAIL %d" % bad))
	get_tree().quit(1 if bad else 0)
