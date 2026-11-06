extends Node3D
# T272 probe (HUMAN_FOUND 2026-11-05: "Missile explosion visual is 20% too big" + "Missiles
# should explode once they hit maximum range, regardless of whether they hit anything"): a
# missile that meets nothing bursts where its range runs out; the real shot splashes an enemy
# there (linear falloff), a client ghost only shows the fireball; the fireball's radius is
# 0.4 x the splash radius (was 0.5).

const SHOT := preload("res://scenes/weapons/ProjectileGrey.tscn")

class Dummy extends Node3D:
	var team := 1
	var taken := 0.0
	func take_damage(a: float, _src = null) -> void:
		taken += a

func _fail(msg: String) -> void:
	push_error("[probe] missile_range_burst FAIL: " + msg)
	get_tree().quit(1)

func _booms() -> Array:
	return get_children().filter(func(n): return n.name.begins_with("Explosion"))

func _ready() -> void:
	get_tree().current_scene = self
	var dummy := Dummy.new()
	add_child(dummy)
	dummy.add_to_group("mechs")
	for ghost in [false, true]:
		dummy.taken = 0.0
		var p: Node3D = SHOT.instantiate()
		p.set("explode", true)
		p.set("splash_radius", 4.0)
		p.set("splash_damage", 15.0)
		p.set("team", 0)
		p.set("speed", 40.0)
		p.set("lifetime", 0.5)  # 20 m of flight, open space
		p.set("is_ghost", ghost)
		add_child(p)
		p.global_transform = Transform3D(Basis(), Vector3.ZERO).looking_at(Vector3(0, 0, -20))
		dummy.global_position = Vector3(1.0, 0, -20)  # 1 m beside where the range ends
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and _booms().is_empty():
			await get_tree().physics_frame
		if _booms().is_empty():
			_fail("a %s missile flew its range and never burst" % ("ghost" if ghost else "real"))
			return
		var boom: Node3D = _booms()[0]
		if absf(boom.global_position.z + 20.0) > 1.5:
			_fail("burst at %s, its range ends at z=-20" % boom.global_position)
			return
		if ghost and dummy.taken > 0.0:
			_fail("a ghost's burst did %.1f damage (ghosts are visual only)" % dummy.taken)
			return
		if not ghost and (dummy.taken < 15.0 * (1.0 - 1.6 / 4.0) or dummy.taken > 15.0 * (1.0 - 0.4 / 4.0)):
			_fail("the burst splashed %.1f on an enemy ~1 m away, want ~11" % dummy.taken)
			return
		var fire_at := Time.get_ticks_msec()
		while Time.get_ticks_msec() - fire_at < 400:
			await get_tree().process_frame
		if is_instance_valid(boom) and boom.get_child_count() > 0:
			var radius: float = (boom.get_child(0) as Node3D).scale.x * 0.5
			if absf(radius - 0.4 * 4.0) > 0.1:
				_fail("fireball radius %.2f m, want 0.4 x splash = 1.60" % radius)
				return
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and not _booms().is_empty():
			await get_tree().physics_frame
	print("[probe] missile_range_burst done")
	get_tree().quit(0)
