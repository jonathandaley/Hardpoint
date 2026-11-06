extends Node3D
# T258 probe (HUMAN_FOUND_ISSUES 2026-11-05 "explosion animation for missile launcher"):
# a missile (Projectile with explode) bursts into an Explosion where it hits a wall --
# both the real shot and a client ghost -- the burst is gone within 1.5 s, and the
# launcher marks its shots explosive and sends ghosts to clients.

const SHOT := preload("res://scenes/weapons/ProjectileGrey.tscn")

func _fail(msg: String) -> void:
	push_error("[probe] missile_explosion FAIL: " + msg)
	get_tree().quit(1)

func _booms() -> Array:
	return get_children().filter(func(n): return n.name.begins_with("Explosion"))

func _ready() -> void:
	get_tree().current_scene = self
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 1)
	cs.shape = box
	wall.add_child(cs)
	add_child(wall)
	wall.position = Vector3(0, 0, -12)
	for i in 3:
		await get_tree().physics_frame
	for ghost in [false, true]:
		var p: Node3D = SHOT.instantiate()
		p.set("explode", true)
		p.set("splash_radius", 4.0)
		p.set("is_ghost", ghost)
		add_child(p)
		p.global_transform = Transform3D(Basis(), Vector3.ZERO).looking_at(Vector3(0, 0, -20))
		var seen := false
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and not seen:
			await get_tree().physics_frame
			seen = not _booms().is_empty()
		if not seen:
			_fail("no Explosion when a %s missile hit the wall" % ("ghost" if ghost else "real"))
			return
		var at: Vector3 = (_booms()[0] as Node3D).global_position
		if absf(at.z + 11.5) > 1.0:
			_fail("explosion at %s, wall face is z=-11.5" % at)
			return
		t0 = Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1500 and not _booms().is_empty():
			await get_tree().physics_frame
		if not _booms().is_empty():
			_fail("explosion still there after 1.5 s")
			return
	var src: String = (load("res://scripts/MissileLauncher.gd") as Script).source_code
	if not src.contains("explode = true") or not src.contains("_rpc_spawn_ghost.rpc("):
		_fail("MissileLauncher does not mark shots explosive / send client ghosts")
		return
	print("[probe] missile_explosion done")
	get_tree().quit(0)
