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

# T255 / T310 (user: "slight variations in the glowing/emissive parts ... No adding anything
# new"; then on attempt 2's four flat shades: "each block of glow is the same color; I meant to
# texture it like the non-emissive parts of the mech (speckle?)"): the glow parts wear the
# mech's own armor speckle -- its tile's brightness squeezed into 0.7-1.0 and tinted the glow
# colour -- with the armor's mapping and pixel size. Same boxes; nothing added.
const GLOW_FLOOR := 0.7
static var _speckles := {}

static func _glow_speckle(tex_path: String, emit: Color, energy: float) -> StandardMaterial3D:
	var key := "%s|%s" % [tex_path, emit.to_html()]
	if not _speckles.has(key):
		var img: Image = (load(tex_path) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGB8)
		var lo := 1.0
		var hi := 0.0
		for y in img.get_height():
			for x in img.get_width():
				var l := img.get_pixel(x, y).get_luminance()
				lo = minf(lo, l)
				hi = maxf(hi, l)
		for y in img.get_height():
			for x in img.get_width():
				var t := (img.get_pixel(x, y).get_luminance() - lo) / maxf(hi - lo, 0.001)
				var k := GLOW_FLOOR + (1.0 - GLOW_FLOOR) * t
				img.set_pixel(x, y, Color(emit.r * k, emit.g * k, emit.b * k))
		var m := _mat_e(Color.WHITE, energy)
		var tex := ImageTexture.create_from_image(img)
		m.albedo_texture = tex
		m.emission = emit
		m.emission_texture = tex
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / TEX_M
		_speckles[key] = m
	return _speckles[key]

## A display mech (hangar lineup, T323 in-match picker) carries `paths` (weapon scene per slot,
## "" = the slot's default), weapons frozen.
static func arm_display(m: Node, md: Resource, paths: Array) -> void:
	var slots: Array = []
	for i in md.weapon_slots.size():
		var sl: Resource = md.weapon_slots[i]
		if i < paths.size() and str(paths[i]) != "" and ResourceLoader.exists(str(paths[i])):
			sl = sl.duplicate()
			sl.weapon_scene = load(str(paths[i]))
		slots.append(sl)
	m.weapon_scale = md.weapon_scale
	m.configure_weapons(slots)
	for c in m.get("torso").get_children():
		if c.name.begins_with("Hardpoint"):
			c.process_mode = Node.PROCESS_MODE_DISABLED

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

# T427: the boxes are merged per material per moving part at the end (_merge_parts).
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
	if k["energy"] > 0.0:  # T310: glow parts speckled like the armor
		mats["E"] = _glow_speckle("res://assets/hardpoint/textures/%s-armor.png" % tex, k["emis"], k["energy"])
	var pick := func(key: String) -> StandardMaterial3D:
		return mats[key]
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		# T218: the physical shield's placeholder too -- the kit model carries its own shield;
		# the blue box showed inside it while the shield was up (Everest, until it broke)
		for n in ["Waist", "Body", "Head", "ShoulderLeft", "ShoulderRight", "PhysicalShield/ShieldMesh"]:
			var old := t.get_node_or_null(n) as MeshInstance3D
			if old:
				old.mesh = null
		for b in k["torso"]:
			var mi := _add_box(t, Vector3(b[3], b[4], b[5]), Vector3(b[0], b[1], b[2]))
			mi.rotation = Vector3(b[6], b[7], b[8])
			_paint(mi, pick.call(b[9]))
	var l := mech.get_node_or_null("Legs") as Node3D
	if l == null:
		return
	var pv: Array = k["pelvis"]
	var hips := l.get_node_or_null("Hips") as MeshInstance3D
	if hips:
		_bm(hips, Vector3(pv[0], pv[1], pv[2]))
		hips.position = Vector3(pv[3], pv[4], pv[5])
		_paint(hips, pick.call(pv[6]))
	for e in k["pelvis_extra"]:
		_paint(_add_box(l, Vector3(e[3], e[4], e[5]), Vector3(e[0], e[1], e[2])), pick.call(e[6]))
	var hb: Array = k["hip"]
	var segs: Array = k["segs"]
	var tp: Array = k["toe"]
	var pad := Vector3(0.0, tp[1] * 0.5 - 0.04, -0.04)  # pad sits on the ground, shin end inside it
	for side in [["Left", -1.0], ["Right", 1.0]]:
		var hip := l.get_node_or_null(side[0] + "Hip") as Node3D
		if hip == null:
			continue
		hip.position.x = side[1] * k["hip_x"]
		_paint(_add_box(l, hip.position, Vector3(hb[0], hb[1], hb[2])), pick.call(hb[3]))
		var k1 := hip.get_node(side[0] + "Knee1") as Node3D
		var k2 := k1.get_node(side[0] + "Knee2") as Node3D
		var seg_nodes: Array = [hip.get_node("Upper" + side[0]), k1.get_node("Mid" + side[0]), k2.get_node("Lower" + side[0])]
		for i in 3:
			_bm(seg_nodes[i], Vector3(segs[i][0], 0.55, segs[i][1]))
			_paint(seg_nodes[i], pick.call(segs[i][2]))
		var foot := Node3D.new()
		foot.name = "Foot"
		foot.position = Vector3(0.0, -0.55, 0.0)
		foot.rotation.x = -_REST_HIP
		k2.add_child(foot)
		_paint(_add_box(foot, pad, Vector3(tp[0], tp[1], tp[2])), pick.call(tp[3]))
		for e in k["leg_extra"]:
			var at: Node3D = {"knee1": k1, "knee2": k2, "foot": foot}[e[0]]
			var off := Vector3(e[4], e[5], e[6]) + (pad if e[0] == "foot" else Vector3.ZERO)
			_paint(_add_box(at, off, Vector3(e[1], e[2], e[3])), pick.call(e[7]))
	_merge_parts(mech)

# T427 (draw calls: ~40 boxes a mech = ~40 draw calls, ~550 a 5v5 frame): the unnamed kit boxes
# (_add_box) that share a parent and a material become ONE mesh, so a moving part draws once per
# material. Named boxes (Hips, the leg segments) stay: code finds them by name. The kit's tiles
# are triplanar in each box's own space; merged boxes would share one space and the tiles would
# slide, so the projection is baked into UVs first: per face, exactly the coordinates Godot's
# triplanar picks (box faces are axis-aligned, so one plane wins outright), and the merged mesh
# draws with a copy of the material that reads those UVs. Same texels, same mip level.
static func _merge_parts(mech: Node3D) -> void:
	var groups := {}  # [parent, material] -> [MeshInstance3D]
	var torso := mech.get_node_or_null("Torso") as Node3D
	var shield := torso.get_node_or_null("PhysicalShield") as Node3D if torso != null else null
	for n in mech.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if not (mi.mesh is BoxMesh) or not String(mi.name).begins_with("@") or mi.get_child_count() > 0:
			continue
		if mi.get_parent() == torso and Mech.in_shield_volume(shield, mi.position):
			continue  # Everest's kit shield: Mech._adopt_shield_meshes moves these under the shield (T242)
		var key := [mi.get_parent(), mi.get_surface_override_material(0)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	var baked := {}  # triplanar material -> its UV copy
	for key in groups:
		var parts: Array = groups[key]
		if parts.size() < 2:
			continue
		var mat := key[1] as StandardMaterial3D
		var tri := mat != null and mat.uv1_triplanar
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in parts:
			var arr: Array = (mi as MeshInstance3D).mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var xf: Transform3D = (mi as MeshInstance3D).transform
			for i in idx:
				var v := verts[i]
				var nm := norms[i]
				st.set_normal((xf.basis * nm).normalized())
				st.set_uv(_triplanar_uv(v, nm, mat.uv1_scale, mat.uv1_offset) if tri else uvs[i])
				st.add_vertex(xf * v)
		var out := MeshInstance3D.new()
		out.mesh = st.commit()
		if tri:
			if not baked.has(mat):
				var m2 := mat.duplicate() as StandardMaterial3D
				m2.uv1_triplanar = false
				m2.uv1_scale = Vector3.ONE
				m2.uv1_offset = Vector3.ZERO
				baked[mat] = m2
			out.set_surface_override_material(0, baked[mat])
		else:
			out.set_surface_override_material(0, mat)
		(key[0] as Node).add_child(out)
		for mi in parts:
			(mi as Node).free()

## Godot's triplanar lookup (BaseMaterial3D, object space): pos = (VERTEX * scale + offset) with
## y flipped; z faces read pos.xy, y faces pos.xz, x faces pos.zy * (-1, 1).
static func _triplanar_uv(v: Vector3, n: Vector3, scale: Vector3, offset: Vector3) -> Vector2:
	var p := (v * scale + offset) * Vector3(1.0, -1.0, 1.0)
	var a := n.abs()
	if a.z >= a.x and a.z >= a.y:
		return Vector2(p.x, p.y)
	if a.y >= a.x:
		return Vector2(p.x, p.z)
	return Vector2(-p.z, p.y)
