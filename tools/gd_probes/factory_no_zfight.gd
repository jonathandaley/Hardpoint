extends Node3D
# T300 + T302 probe (HUMAN_FOUND 2026-11-05: Factory "should have less atmospheric haze";
# "yellow bands around some of the buildings are at the same depth, so flicker"): no glowing
# (emissive light-strip) box on the Factory map shares a face plane, facing the same way with
# overlapping area, with any other box (that is what z-fights); the fog is light (<= 0.002).

func _fail(msg: String) -> void:
	push_error("[probe] factory_no_zfight FAIL: " + msg)

func _aabb(mi: MeshInstance3D) -> AABB:
	var sz: Vector3 = (mi.mesh as BoxMesh).size * mi.global_transform.basis.get_scale()
	return AABB(mi.global_position - sz * 0.5, sz)

func _ready() -> void:
	var we := WorldEnvironment.new()  # the map takes the arena's environment as its own
	we.name = "WorldEnvironment"
	we.environment = Environment.new()
	add_child(we)
	var md: Resource = load("res://resources/maps/Factory.tres")
	var map: Node3D = (load(md.get("scene_path")) as PackedScene).instantiate()
	add_child(map)
	map.call("build")
	await get_tree().process_frame
	var boxes: Array = []
	var glow: Array = []
	for n in map.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not (mi.mesh is BoxMesh) or not mi.global_transform.basis.is_equal_approx(Basis().scaled(mi.global_transform.basis.get_scale())):
			continue  # axis-aligned boxes only
		boxes.append(mi)
		var mat := mi.material_override as StandardMaterial3D
		if mat != null and mat.emission_enabled:
			glow.append(mi)
	var hits := 0
	for g: MeshInstance3D in glow:
		var a := _aabb(g)
		for o: MeshInstance3D in boxes:
			if o == g:
				continue
			var b := _aabb(o)
			for ax in 3:
				var u := (ax + 1) % 3
				var v := (ax + 2) % 3
				var ou := minf(a.end[u], b.end[u]) - maxf(a.position[u], b.position[u])
				var ov := minf(a.end[v], b.end[v]) - maxf(a.position[v], b.position[v])
				if ou <= 0.01 or ov <= 0.01:
					continue
				for side in [0, 1]:
					var pa: float = a.position[ax] if side == 0 else a.end[ax]
					var pb: float = b.position[ax] if side == 0 else b.end[ax]
					if ax == 1 and side == 0 and pa < 0.05:
						continue  # a downward face lying on the deck is never seen
					if absf(pa - pb) < 0.002:
						hits += 1
						if hits <= 5:
							_fail("glow box at %s shares its %s%s face with the box at %s" % [g.global_position, "-+"[side], "xyz"[ax], o.global_position])
	var env: Environment = we.environment
	if env != null and env.fog_enabled and env.fog_density > 0.002:
		_fail("fog density %.4f, want <= 0.002" % env.fog_density)
		hits += 1
	if env == null:
		_fail("found no environment to check the haze")
		hits += 1
	if hits > 0:
		get_tree().quit(1)
		return
	print("[probe] factory_no_zfight done (%d glow boxes vs %d boxes)" % [glow.size(), boxes.size()])
	get_tree().quit(0)
