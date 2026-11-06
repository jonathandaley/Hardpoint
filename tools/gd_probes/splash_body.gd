extends Node3D
# T327 probe (user 2026-11-05: "Yes" -- splash measured to the nearest point of the mech, not
# its feet): a missile burst 1 m in front of a mech's chest splashes it as from 0.5 m away
# (capsule radius 0.5), not from its feet ~2.2 m off; a burst inside the body is full damage;
# rockets / aerial strikes (HomingProjectile) measure the same way.

const SHOT := preload("res://scenes/weapons/ProjectileGrey.tscn")

class Dummy extends Node3D:
	var team := 1
	var taken := 0.0
	func take_damage(a: float, _src = null) -> void:
		taken += a

func _ready() -> void:
	get_tree().current_scene = self
	var mech := Dummy.new()  # Mech.tscn's body: a capsule r 0.5 h 2 at (0, 1, 0)
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 2.0
	cs.shape = cap
	cs.position = Vector3(0, 1, 0)
	mech.add_child(cs)
	add_child(mech)
	mech.add_to_group("mechs")
	await get_tree().physics_frame
	var msg := ""
	var d := Projectile.mech_distance(mech, Vector3(0, 1.5, -1.0))
	if absf(d - 0.5) > 0.01:
		msg = "chest-height burst 1 m out measured %.2f m, want 0.50 (to the body)" % d
	elif Projectile.mech_distance(mech, Vector3(0, 1.0, 0.2)) > 0.0:
		msg = "a burst inside the body isn't at distance 0"
	if msg == "":
		var p: Node3D = SHOT.instantiate()
		p.set("explode", true)
		p.set("splash_radius", 4.0)
		p.set("splash_damage", 16.0)
		p.set("team", 0)
		p.set("speed", 0.01)
		p.set("lifetime", 0.05)
		add_child(p)
		p.global_position = Vector3(0, 1.5, -1.0)
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1000 and mech.taken == 0.0:
			await get_tree().physics_frame
		if absf(mech.taken - 16.0 * (1.0 - 0.5 / 4.0)) > 0.3:
			msg = "the burst splashed %.1f, want %.1f (0.5 m from the body)" % [mech.taken, 16.0 * (1.0 - 0.5 / 4.0)]
	if msg == "" and not (load("res://scripts/HomingProjectile.gd") as Script).source_code.contains("Projectile.mech_distance("):
		msg = "HomingProjectile (rockets / aerial strike) still measures splash to the mech's origin"
	if msg != "":
		push_error("[probe] splash_body FAIL: " + msg)
		get_tree().quit(1)
		return
	print("[probe] splash_body done")
	get_tree().quit(0)
