class_name MechVisuals

# Apply per-mech body geometry. Call after instantiate() but before add_child()
# so accessories are present when Mech._ready() builds _body_meshes.
static func apply(mech: Node3D, display_name: String) -> void:
	# T178: the design kit's box models (tools/kit_port.py -> MechKit.gd); Lynx and Warhog
	# have no kit render yet and keep their hand-made builders.
	if MechKit.DATA.has(display_name):
		_kit(mech, MechKit.DATA[display_name])
		return
	match display_name:
		"Lynx":       _lynx(mech)
		"Warhog":     _warhog(mech)


# ---- mesh setters ----

static func _bm(mi: MeshInstance3D, sz: Vector3) -> void:
	if mi == null:
		return
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m

static func _cyl(mi: MeshInstance3D, tr: float, br: float, h: float, segs: int = 16) -> void:
	if mi == null:
		return
	var m := CylinderMesh.new()
	m.top_radius = tr
	m.bottom_radius = br
	m.height = h
	m.radial_segments = segs
	mi.mesh = m

# ---- material helpers ----

static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	return m

# T178: unshaded draws albedo only, so a black albedo left every glow part black;
# the glow colour is the albedo (emission still feeds glow/bloom where enabled).
static func _mat_e(_col: Color, emit: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = emit
	m.emission_enabled = true
	m.emission = emit
	m.emission_energy_multiplier = energy
	return m

static func _paint(mi: MeshInstance3D, mat: StandardMaterial3D) -> void:
	if mi:
		mi.set_surface_override_material(0, mat)

static func _paint_all(parent: Node3D, mat: StandardMaterial3D) -> void:
	if parent == null:
		return
	for child in parent.find_children("*", "MeshInstance3D", true, false):
		(child as MeshInstance3D).set_surface_override_material(0, mat)


# ---- accessory factories (added as Torso or Legs children) ----

static func _add_box(parent: Node3D, pos: Vector3, sz: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_cyl(parent: Node3D, pos: Vector3, tr: float, br: float, h: float, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = tr
	m.bottom_radius = br
	m.height = h
	m.radial_segments = segs
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---- leg segment helpers ----

static func _leg_segs(l: Node3D, upper: Vector3, mid: Vector3, lower: Vector3) -> void:
	_bm(l.get_node_or_null("LeftHip/UpperLeft") as MeshInstance3D,                         upper)
	_bm(l.get_node_or_null("RightHip/UpperRight") as MeshInstance3D,                       upper)
	_bm(l.get_node_or_null("LeftHip/LeftKnee1/MidLeft") as MeshInstance3D,                 mid)
	_bm(l.get_node_or_null("RightHip/RightKnee1/MidRight") as MeshInstance3D,              mid)
	_bm(l.get_node_or_null("LeftHip/LeftKnee1/LeftKnee2/LowerLeft") as MeshInstance3D,     lower)
	_bm(l.get_node_or_null("RightHip/RightKnee1/RightKnee2/LowerRight") as MeshInstance3D, lower)

# Heavy class: thick pillar legs
static func _heavy_legs(l: Node3D) -> void:
	_leg_segs(l, Vector3(0.28, 0.55, 0.26), Vector3(0.26, 0.55, 0.24), Vector3(0.24, 0.55, 0.22))


# ==== T178: design-kit mechs ====

const MechKit := preload("res://scripts/MechKit.gd")  # generated data (tools/kit_port.py)

const _KIT_MOUNT  := Color(0.169, 0.169, 0.204)  # kit NEUTRAL_MOUNT 0x2b2b34
const _KIT_SOCKET := Color(0.078, 0.078, 0.102)  # kit NEUTRAL_SOCKET 0x14141a
const _REST_HIP   := 0.524  # BipedLegs.REST_HIP: the shin end sits at this pitch; the foot undoes it

# ponytail: one MeshInstance per kit box (~40 per mech, ~400 draw calls in a 5v5);
# merge per material with SurfaceTool if rendering ever shows up in profiling.
# Torso boxes as authored. Legs keep the game's animated rig (BipedLegs gait needs its
# 0.55 m segments): kit span thickness/depth, hip blocks at the kit's hip spacing, the
# pelvis, a level toe pad at each shin end, and leg lights on the nearest joint.
static func _kit(mech: Node3D, k: Dictionary) -> void:
	var mats := {
		"A": _mat(k["armor"]), "D": _mat(k["detail"]), "MO": _mat(_KIT_MOUNT), "SO": _mat(_KIT_SOCKET),
		"E": _mat_e(Color(0, 0, 0), k["emis"], k["energy"]) if k["energy"] > 0.0 else _mat(k["detail"]),
	}
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		for n in ["Waist", "Body", "Head", "ShoulderLeft", "ShoulderRight"]:
			var old := t.get_node_or_null(n) as MeshInstance3D
			if old:
				old.mesh = null
		for b in k["torso"]:
			var mi := _add_box(t, Vector3(b[3], b[4], b[5]), Vector3(b[0], b[1], b[2]))
			mi.rotation = Vector3(b[6], b[7], b[8])
			_paint(mi, mats[b[9]])
	var l := mech.get_node_or_null("Legs") as Node3D
	if l == null:
		return
	var pv: Array = k["pelvis"]
	var hips := l.get_node_or_null("Hips") as MeshInstance3D
	if hips:
		_bm(hips, Vector3(pv[0], pv[1], pv[2]))
		hips.position = Vector3(pv[3], pv[4], pv[5])
		_paint(hips, mats[pv[6]])
	for e in k["pelvis_extra"]:
		_paint(_add_box(l, Vector3(e[3], e[4], e[5]), Vector3(e[0], e[1], e[2])), mats[e[6]])
	var hb: Array = k["hip"]
	var segs: Array = k["segs"]
	var tp: Array = k["toe"]
	var pad := Vector3(0.0, tp[1] * 0.5 - 0.04, -0.04)  # pad sits on the ground, shin end inside it
	for side in [["Left", -1.0], ["Right", 1.0]]:
		var hip := l.get_node_or_null(side[0] + "Hip") as Node3D
		if hip == null:
			continue
		hip.position.x = side[1] * k["hip_x"]
		_paint(_add_box(l, hip.position, Vector3(hb[0], hb[1], hb[2])), mats[hb[3]])
		var k1 := hip.get_node(side[0] + "Knee1") as Node3D
		var k2 := k1.get_node(side[0] + "Knee2") as Node3D
		var seg_nodes: Array = [hip.get_node("Upper" + side[0]), k1.get_node("Mid" + side[0]), k2.get_node("Lower" + side[0])]
		for i in 3:
			_bm(seg_nodes[i], Vector3(segs[i][0], 0.55, segs[i][1]))
			_paint(seg_nodes[i], mats[segs[i][2]])
		var foot := Node3D.new()
		foot.name = "Foot"
		foot.position = Vector3(0.0, -0.55, 0.0)
		foot.rotation.x = -_REST_HIP
		k2.add_child(foot)
		_paint(_add_box(foot, pad, Vector3(tp[0], tp[1], tp[2])), mats[tp[3]])
		for e in k["leg_extra"]:
			var at: Node3D = {"knee1": k1, "knee2": k2, "foot": foot}[e[0]]
			var off := Vector3(e[4], e[5], e[6]) + (pad if e[0] == "foot" else Vector3.ZERO)
			_paint(_add_box(at, off, Vector3(e[1], e[2], e[3])), mats[e[7]])


# ==== per-mech designs (no kit render yet) ====
# All positions are in Torso-space (Torso node is at mech root, no offset).
# Mech faces -Z. +Z is back. +X is left when facing mech from front.
# Key Torso-space landmarks (default): Waist Y=1.02, Body Y=1.42, Shoulders Y=1.72 +/-0.68X, Head Y=1.92


# Lynx: lithe cat silhouette -- forest green, amber antenna glow
static func _lynx(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.22, 0.40, 0.22))
	var detail := _mat(Color(0.14, 0.26, 0.14))
	var glow   := _mat_e(Color(0, 0, 0), Color(1.0, 0.65, 0.05), 2.5)
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_cyl(body, 0.30, 0.38, 0.58)
		_bm(waist, Vector3(0.56, 0.14, 0.56))
		_bm(head,  Vector3(0.32, 0.26, 0.46))
		_bm(sl, Vector3(0.16, 0.18, 0.50))
		_bm(sr, Vector3(0.16, 0.18, 0.50))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		_paint(body, armor); _paint(waist, armor); _paint(head, armor)
		_paint(sl, armor);   _paint(sr, armor)
		# antenna spike
		_paint(_add_box(t, Vector3(0.0, 2.10, 0.0),      Vector3(0.04, 0.20, 0.04)), glow)
		# neck cylinder
		_paint(_add_cyl(t, Vector3(0.0, 1.75, 0.0),      0.16, 0.18, 0.08), armor)
		# cat ear spikes
		_paint(_add_box(t, Vector3(-0.11, 2.08, 0.0),    Vector3(0.04, 0.14, 0.04)), glow)
		_paint(_add_box(t, Vector3( 0.11, 2.08, 0.0),    Vector3(0.04, 0.14, 0.04)), glow)
		# shoulder-body connector brackets
		_paint(_add_box(t, Vector3(-0.44, 1.72, 0.0),    Vector3(0.16, 0.10, 0.36)), detail)
		_paint(_add_box(t, Vector3( 0.44, 1.72, 0.0),    Vector3(0.16, 0.10, 0.36)), detail)
		# lower back tail stub
		_paint(_add_box(t, Vector3(0.0, 1.26, 0.40),     Vector3(0.06, 0.08, 0.04)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.80, 0.18, 0.46))
		_leg_segs(l, Vector3(0.17, 0.64, 0.16), Vector3(0.15, 0.64, 0.14), Vector3(0.13, 0.20, 0.28))
		_paint_all(l, armor)


# Warhog: brutish boar tank -- mud brown, no emissive (pure grit)
static func _warhog(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	var armor  := _mat(Color(0.36, 0.30, 0.20))
	var detail := _mat(Color(0.48, 0.40, 0.26))
	if t:
		var body  := t.get_node_or_null("Body") as MeshInstance3D
		var waist := t.get_node_or_null("Waist") as MeshInstance3D
		var head  := t.get_node_or_null("Head") as MeshInstance3D
		var sl    := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr    := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(body,  Vector3(1.12, 0.64, 0.88))
		_bm(waist, Vector3(0.84, 0.22, 0.76))
		_bm(head,  Vector3(0.44, 0.28, 0.58))
		_bm(sl, Vector3(0.36, 0.32, 0.68))
		_bm(sr, Vector3(0.36, 0.32, 0.68))
		if head:
			head.position.y = 1.82
			head.position.z = -0.08
		if sl: sl.position.x = -0.78
		if sr: sr.position.x =  0.78
		_paint(body, armor); _paint(waist, armor); _paint(head, detail)
		_paint(sl, armor);   _paint(sr, armor)
		# tusks
		_paint(_add_box(t, Vector3(-0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22)), detail)
		_paint(_add_box(t, Vector3( 0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22)), detail)
		# tusk root brackets
		_paint(_add_box(t, Vector3(-0.14, 1.68, -0.40), Vector3(0.10, 0.08, 0.06)), armor)
		_paint(_add_box(t, Vector3( 0.14, 1.68, -0.40), Vector3(0.10, 0.08, 0.06)), armor)
		# armored nose plate
		_paint(_add_box(t, Vector3(0.0, 1.84, -0.40),  Vector3(0.32, 0.18, 0.06)), detail)
		# shoulder-body connector plates
		_paint(_add_box(t, Vector3(-0.58, 1.72, 0.0),  Vector3(0.08, 0.26, 0.50)), armor)
		_paint(_add_box(t, Vector3( 0.58, 1.72, 0.0),  Vector3(0.08, 0.26, 0.50)), armor)
		# command hatch on body top
		_paint(_add_box(t, Vector3(0.0, 1.75, 0.0),    Vector3(0.22, 0.02, 0.32)), detail)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.12, 0.26, 0.64))
		_heavy_legs(l)
		_paint_all(l, armor)
