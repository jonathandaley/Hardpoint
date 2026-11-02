class_name MechVisuals

# Apply per-mech body geometry. Call after instantiate() but before add_child()
# so accessories are present when Mech._ready() builds _body_meshes.
static func apply(mech: Node3D, display_name: String) -> void:
	# T178/T181: every mech is a design-kit box model (tools/kit_port.py -> MechKit.gd)
	if MechKit.DATA.has(display_name):
		_kit(mech, MechKit.DATA[display_name], display_name.to_lower())


# ---- mesh setters ----

static func _bm(mi: MeshInstance3D, sz: Vector3) -> void:
	if mi == null:
		return
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m

# ---- material helpers ----

# T179 (G25): lit, so box faces shade differently and forms read (unshaded mechs were
# flat silhouettes; the kit renders are Lambert-lit). Matte: no specular sheen.
static func _mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

# T182: the kit's pixel tile (armor/detail, see tools/kit_tiles.gd) at the kit's constant
# texel size, TEX_REF 1.16 m per tile. Triplanar in the box's own space is a planar
# projection per face, so the BoxMeshes need no UVs.
const TEX_M := 1.16
static func _mat_tex(path: String) -> StandardMaterial3D:
	var m := _mat(Color.WHITE)
	m.albedo_texture = load(path)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE / TEX_M
	return m

# T178: unshaded draws albedo only, so a black albedo left every glow part black;
# the glow colour is the albedo (emission still feeds glow/bloom where enabled).
static func _mat_e(emit: Color, energy: float) -> StandardMaterial3D:
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

# ---- accessory factories (added as Torso or Legs children) ----

static func _add_box(parent: Node3D, pos: Vector3, sz: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi

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
static func _kit(mech: Node3D, k: Dictionary, tex: String) -> void:
	var detail := _mat_tex("res://assets/hardpoint/textures/%s-detail.png" % tex)
	var mats := {
		"A": _mat_tex("res://assets/hardpoint/textures/%s-armor.png" % tex), "D": detail,
		"MO": _mat(_KIT_MOUNT), "SO": _mat(_KIT_SOCKET),
		"E": _mat_e(k["emis"], k["energy"]) if k["energy"] > 0.0 else detail,
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
