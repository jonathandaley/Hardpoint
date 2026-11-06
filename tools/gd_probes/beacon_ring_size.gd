extends Node3D
# T314 probe (HUMAN_FOUND 2026-11-05: "Beacon takeover ring should double in diameter"):
# the ring is 12 m across (radius 6, was 3) and still marks the capture zone exactly -- the
# CaptureZone cylinder has the same radius. (Pads / obstacles vs the bigger ring: probe
# beacon_ring.)

func _ready() -> void:
	var b: Node3D = (load("res://scenes/beacon/Beacon.tscn") as PackedScene).instantiate()
	add_child(b)
	await get_tree().process_frame
	var zone := (b.get_node("CaptureZone/ZoneShape") as CollisionShape3D).shape as CylinderShape3D
	var ring: TorusMesh = null
	for mi in b.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh is TorusMesh:
			ring = (mi as MeshInstance3D).mesh
	var msg := ""
	if ring == null:
		msg = "no ring"
	elif absf(ring.outer_radius - 6.0) > 0.01:
		msg = "ring radius %.2f, want 6 (12 m across)" % ring.outer_radius
	elif absf(zone.radius - ring.outer_radius) > 0.01:
		msg = "capture zone radius %.2f but the ring shows %.2f" % [zone.radius, ring.outer_radius]
	if msg != "":
		push_error("[probe] beacon_ring_size FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] beacon_ring_size done")
	get_tree().quit(0)
