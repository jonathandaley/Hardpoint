extends Node
# T231 probe (HUMAN_FOUND_ISSUES 2026-11-04: "Sydney feels too open"): street-level points
# every 8 m with no solid within 20 m in any of 8 directions (no cover to run to) must be at
# most MAX_OPEN of the walkable ground. Before T231: 25%.
const MAX_OPEN := 0.12

func _fail(msg: String) -> void:
	push_error("[probe] sydney_open: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["map_def"] = load("res://resources/maps/City.tres")
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 5:
		await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = (arena as Node3D).get_world_3d().direct_space_state
	var total := 0
	var open := 0
	var x := -140.0
	while x <= 140.0:
		var z := -110.0
		while z <= 140.0:
			var p := Vector3(x, 1.5, z)
			var inside := PhysicsPointQueryParameters3D.new()
			inside.position = p
			if space.intersect_point(inside).is_empty():
				total += 1
				var hit := false
				for k in 8:
					var a := k * TAU / 8.0
					var q := PhysicsRayQueryParameters3D.create(p, p + Vector3(cos(a), 0, sin(a)) * 20.0)
					var r: Dictionary = space.intersect_ray(q)
					if not r.is_empty() and not (r.collider is CharacterBody3D):
						hit = true
						break
				if not hit:
					open += 1
			z += 8.0
		x += 8.0
	if float(open) / total > MAX_OPEN:
		_fail("%d / %d street points (%.0f%%) have no cover within 20 m (max %.0f%%)" % [open, total, 100.0 * open / total, MAX_OPEN * 100.0])
	print("[probe] sydney_open done (%d / %d street points open, %.0f%%)" % [open, total, 100.0 * open / total])
	get_tree().quit(0)
