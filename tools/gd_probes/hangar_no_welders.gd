extends Node
# T286 probe (HUMAN_FOUND 2026-11-05: "Remove the two big stationary drones in the hangar"):
# the hangar bay builds no welder drones (the 1.6x hovering ones over the repair bays); the
# roaming T254 swarm drones are untouched (probe fancy_hangar).

func _ready() -> void:
	var b: Node3D = load("res://scripts/HangarBay.gd").new()
	add_child(b)
	var big := b.get_children().filter(func(n): return n is Node3D and not n.name.begins_with("SwarmDrone") and is_equal_approx((n as Node3D).scale.x, 1.6))
	if not big.is_empty() or (load("res://scripts/HangarBay.gd") as Script).source_code.contains("func _welder"):
		push_error("[probe] hangar_no_welders FAIL: %d big stationary drones in the bay" % big.size())
		get_tree().quit(1)
		return
	print("[probe] hangar_no_welders done")
	get_tree().quit(0)
