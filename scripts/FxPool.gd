extends Node3D
# T525 (user 2026-11-19: the browser "did lag with lots of MGs going"; Firefox, all bots on heavy MGs:
# draws 320 -> 650 in a fight, 70 -> 20-30 fps): every short-lived effect piece -- muzzle flash, hit
# spark, tracer, explosion core / chunk / debris -- was its own node with its own material and tween,
# so one draw call each (~0.025 ms apiece in Firefox) plus a node to build and free. Now each piece is
# one instance of one of two MultiMeshes (spheres, boxes): 2 draw calls however many are flying.
# Each piece moves / scales / fades linearly from a start to an end state over its life (the old
# tweens set an ease without a transition, which Godot's linear transition ignores -- linear it is),
# except a tracer's fade, quadratic ease-in as before. The old materials' emission showed nothing (unshaded,
# Compatibility renderer, no glow: renders matched) -- the energies are kept for T523 effects. Cosmetic, local on every peer;
# none on a dedicated server. Full -> the oldest piece is reused.

const CAP := [1024, 256]  # spheres, boxes
enum { SPHERE, BOX }

var _mmi: Array[MultiMeshInstance3D] = []
var _buf: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
# per live piece, per layer: [t, dur, delay, p0, p1, basis (orientation, unit), s0, s1, col, e0, e1, a0, a1, quad_alpha]
var _live: Array = [[], []]

func _ready() -> void:
	name = "FxPool"
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	for k in 2:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		if k == BOX:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA  # tracers fade out
		var mesh: Mesh = sphere if k == SPHERE else box
		mesh.surface_set_material(0, mat)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = CAP[k]
		mm.visible_instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 16384.0  # pieces are anywhere: never cull the whole set
		add_child(mmi)
		_mmi.append(mmi)
		_buf[k].resize(CAP[k] * 16)  # once: each frame fills the live front of it

## A sphere piece: radius r0 -> r1 (m), p0 -> p1, energy e0 -> e1, over dur s after delay s.
func sphere(p0: Vector3, p1: Vector3, r0: float, r1: float, col: Color, e0: float, e1: float, dur: float, delay := 0.0) -> void:
	_add(SPHERE, [0.0, dur, delay, p0, p1, Basis.IDENTITY, Vector3.ONE * r0, Vector3.ONE * r1, col, e0, e1, 1.0, 1.0, false])

## A tracer: a box from -> to, width w0 -> w1 across, energy e0 -> 0 and alpha 1 -> 0 (quadratic ease-in).
func beam(from: Vector3, to: Vector3, w0: float, w1: float, col: Color, e0: float, dur: float) -> void:
	var d := to - from
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var b := Basis.looking_at(d, up)
	var mid := (from + to) * 0.5
	var l := d.length()
	_add(BOX, [0.0, dur, 0.0, mid, mid, b, Vector3(w0, w0, l), Vector3(w1, w1, l), col, e0, 0.0, 1.0, 0.0, true])

# Bullets in flight (Projectile with a plain sphere mesh): [node, radius, colour] -- drawn where the node
# is each frame as part of the sphere set; a freed one drops out.
var _follow: Array = []

func follow(n: Node3D, radius: float, col: Color) -> void:
	_follow.append([n, radius, col])

func _add(k: int, piece: Array) -> void:
	var live: Array = _live[k]
	if live.size() >= CAP[k]:
		live.pop_front()  # ponytail: O(n) shift at the cap; a ring index if the cap is ever hit often
	live.append(piece)

func _process(delta: float) -> void:
	if not Game.prof_on:  # T165 profiling shim
		_process_impl(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_impl(delta)
	Game.prof_add("fx", Time.get_ticks_usec() - t0)

func _process_impl(delta: float) -> void:
	for k in 2:
		var live: Array = _live[k]
		var mm := _mmi[k].multimesh
		var i := 0
		while i < live.size():
			var pc: Array = live[i]
			pc[0] += delta
			if float(pc[0]) >= float(pc[2]) + float(pc[1]):
				live[i] = live[live.size() - 1]  # swap-remove: order doesn't matter
				live.pop_back()
				continue
			i += 1
		if k == SPHERE:
			var f := 0
			while f < _follow.size():
				if is_instance_valid(_follow[f][0]) and (_follow[f][0] as Node3D).is_inside_tree():
					f += 1
				else:
					_follow[f] = _follow[_follow.size() - 1]
					_follow.pop_back()
		var n := live.size()
		var buf: PackedFloat32Array = _buf[k]
		for j in n:
			var pc: Array = live[j]
			var u: float = clampf((float(pc[0]) - float(pc[2])) / float(pc[1]), 0.0, 1.0)
			var on: bool = float(pc[0]) >= float(pc[2])
			var p: Vector3 = (pc[3] as Vector3).lerp(pc[4], u)
			var s: Vector3 = (pc[6] as Vector3).lerp(pc[7], u) if on else Vector3.ZERO
			var bs: Basis = (pc[5] as Basis).scaled_local(s) if k == BOX else Basis.from_scale(s)
			var a: float = lerpf(pc[11], pc[12], u * u if pc[13] else u)
			var c: Color = pc[8]
			var o := j * 16
			buf[o] = bs.x.x; buf[o + 1] = bs.y.x; buf[o + 2] = bs.z.x; buf[o + 3] = p.x
			buf[o + 4] = bs.x.y; buf[o + 5] = bs.y.y; buf[o + 6] = bs.z.y; buf[o + 7] = p.y
			buf[o + 8] = bs.x.z; buf[o + 9] = bs.y.z; buf[o + 10] = bs.z.z; buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = a
		if k == SPHERE:
			for fw in _follow:
				if n >= CAP[k]:
					break
				var p: Vector3 = (fw[0] as Node3D).global_position
				var r: float = fw[1]
				var c: Color = fw[2]
				var o := n * 16
				buf[o] = r; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p.x
				buf[o + 4] = 0.0; buf[o + 5] = r; buf[o + 6] = 0.0; buf[o + 7] = p.y
				buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = r; buf[o + 11] = p.z
				buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = 1.0
				n += 1
		if n > 0:
			mm.buffer = buf
		_buf[k] = buf
		mm.visible_instance_count = n
