extends Node3D
# T316 probe (user 2026-11-05: the bullet impact sound "should not play for laser, arc, or
# patience. Any raycast weapons added in the future, either"): a hit confirmed the raycast way
# (no projectile) plays no hit_impact sound for any weapon, the beam / hitscan weapons included;
# a projectile's hit still does; and every projectile on_hit passes by_projectile.

const HITSCAN := ["LaserCannonLight", "LaserCannonHeavy", "ArcWeaponLight", "ArcWeaponHeavy", "PatienceHeavy"]

func _impacts() -> int:
	return get_tree().root.get_children().filter(func(n): return n is AudioStreamPlayer3D and (n as AudioStreamPlayer3D).stream != null and (n as AudioStreamPlayer3D).stream.resource_path.ends_with("hit_impact.wav")).size()

func _fail(msg: String) -> void:
	push_error("[probe] impact_sound FAIL: " + msg)

func _ready() -> void:
	await get_tree().process_frame  # root is busy during _ready: SoundManager's add_child would fail
	var dummy := Node3D.new()
	add_child(dummy)
	dummy.global_position = Vector3(0, 1, -10)
	var bad := false
	for n in HITSCAN + ["RifleLight"]:
		var w: Node = (load("res://scenes/weapons/%s.tscn" % n) as PackedScene).instantiate()
		add_child(w)
		var before := _impacts()
		w.call("_emit_hit_if_visible", dummy, dummy.global_position)
		if _impacts() > before:
			_fail("%s: a raycast-style hit played the impact sound" % n)
			bad = true
		if n == "RifleLight":
			before = _impacts()
			w.call("_emit_hit_if_visible", dummy, dummy.global_position, true)
			if _impacts() <= before:
				_fail("a projectile hit no longer plays the impact sound")
				bad = true
		w.queue_free()
	for f in DirAccess.get_files_at("res://scripts"):
		if f.ends_with(".gd"):
			var src: String = (load("res://scripts/" + f) as Script).source_code
			if src.contains("on_hit = func(body, pos): _emit_hit_if_visible(body, pos)"):
				_fail("%s: a projectile's on_hit doesn't pass by_projectile" % f)
				bad = true
	if bad:
		get_tree().quit(1)
		return
	print("[probe] impact_sound done")
	get_tree().quit(0)
