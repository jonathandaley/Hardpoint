extends RefCounted
# T180: weapon models from the design kit (weapon-builders.js -> tools/kit_port.py ->
# WeaponKit.gd) replace each weapon scene's placeholder meshes. Mech.configure_weapons
# calls apply() on every weapon before it enters the tree.
#
# A kit weapon is 11..93 boxes (Aerial Strike). Boxes are merged into one mesh per
# material, built once per (model, slot size) and shared by every copy, so a weapon
# costs a handful of draw calls. One surface per MeshInstance keeps Mech stealth
# (surface 0 override) and hit flash (material_override) working unchanged.

const WeaponKit := preload("res://scripts/WeaponKit.gd")
const LIGHT_SCALE := 0.5   # kit rifle 1.96 m -> ~1 m, the old light placeholder length
const HEAVY_SCALE := 0.8   # heavy placeholders ran ~1.6x the light ones
const _TEX := {  # T182: kit weapon tiles, same texel size as the mechs
	"A": "res://assets/hardpoint/textures/weapon-steel-armor.png",
	"D": "res://assets/hardpoint/textures/weapon-steel-detail.png",
}
const _COLORS := {
	"MI": Color(0.184, 0.200, 0.231),  # kit matMid 0x2f333b
	"K": Color(0.090, 0.094, 0.114),   # kit matDark 0x17181d
	"MO": Color(0.169, 0.169, 0.204),  # kit NEUTRAL_MOUNT
	"SO": Color(0.078, 0.078, 0.102),  # kit NEUTRAL_SOCKET
}

static var _meshes := {}  # "Rifle@0.5" -> [[ArrayMesh, Material], ...]

## Kit model name for a weapon scene ("RifleHeavy" -> "Rifle", "MissileLauncherLight" -> "MissileL").
static func kit_name(scene_path: String) -> String:
	var base := scene_path.get_file().get_basename()
	var fam := base.trim_suffix("Light").trim_suffix("Heavy")
	if fam == "MissileLauncher":
		return "MissileH" if base.ends_with("Heavy") else "MissileL"
	return fam

## T381 (HUMAN_FOUND 2026-11-09: aerial strike "too big on Seeker"): the strike pod is already a
## bulky box, so a mech's weapon_scale (Seeker 2.0, made for slim guns: T191) caps here.
const MULT_CAP := {"AerialStrike": 1.2}

static func apply(weapon: Node3D, mult := 1.0) -> void:
	var key := kit_name(weapon.scene_file_path)
	if not WeaponKit.DATA.has(key):
		return
	mult = minf(mult, MULT_CAP.get(key, mult))
	for c in weapon.get_children():
		if c is MeshInstance3D:  # placeholder geometry only (no script reads these nodes)
			weapon.remove_child(c)
			c.free()
	var heavy: bool = int(weapon.get("slot_size")) == 1
	for part in _parts(key, (HEAVY_SCALE if heavy else LIGHT_SCALE) * mult):  # T191: per-mech size
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.set_surface_override_material(0, part[1])
		weapon.add_child(mi)
	if "visual_scale" in weapon:
		weapon.set("visual_scale", mult)  # muzzle flash at the bigger barrel's end
	# T317 (HUMAN_FOUND 2026-11-05: muzzle flash "actually at the end of the barrel and not at
	# its base. Make its size proportional to the barrel"): the model's real muzzle + width
	var mz: Array = _muzzle(key)
	var s := (HEAVY_SCALE if heavy else LIGHT_SCALE) * mult
	weapon.set("muzzle_local", (mz[0] as Vector3) * s)
	weapon.set("barrel_w", float(mz[1]) * s)

static var _muzzles := {}

## [muzzle point, barrel width] in kit units. The front plane's boxes (within 2 cm of the most
## forward point) make the muzzle: the centre of their outline (a missile pod's tube grid ->
## the pod's centre), barrel width = the widest of them (one tube, one barrel).
static func _muzzle(key: String) -> Array:
	if _muzzles.has(key):
		return _muzzles[key]
	var boxes: Array = WeaponKit.DATA[key]
	var front := INF
	for b in boxes:
		front = minf(front, _front_z(b))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var w := 0.0
	for b in boxes:
		if _front_z(b) <= front + 0.01:
			lo = Vector2(minf(lo.x, float(b[3])), minf(lo.y, float(b[4])))
			hi = Vector2(maxf(hi.x, float(b[3])), maxf(hi.y, float(b[4])))
			w = maxf(w, maxf(float(b[0]), float(b[1])))
	var c := (lo + hi) * 0.5
	var out := [Vector3(c.x, c.y, front), w]
	_muzzles[key] = out
	return out

## The box's most forward z (kit boxes can be rotated: Aerial Strike's fins).
static func _front_z(b: Array) -> float:
	var r := Basis(Quaternion(float(b[6]), float(b[7]), float(b[8]), float(b[9])))
	var hz := absf(r.x.z) * float(b[0]) * 0.5 + absf(r.y.z) * float(b[1]) * 0.5 + absf(r.z.z) * float(b[2]) * 0.5
	return float(b[5]) - hz

static func _parts(key: String, s: float) -> Array:
	var ck := "%s@%s" % [key, s]
	if _meshes.has(ck):
		return _meshes[ck]
	var tools := {}
	for i in WeaponKit.DATA[key].size():
		var b: Array = WeaponKit.DATA[key][i]
		var st: SurfaceTool = tools.get(b[10])
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[b[10]] = st
		# golden-ratio offsets: neighbouring boxes don't show the same texel pattern (kit randomises)
		var off := Vector2(fposmod(i * 0.618, 1.0), fposmod(i * 0.382, 1.0))
		st.append_from(_box(Vector3(b[0], b[1], b[2]) * s, off), 0, Transform3D(Basis(Quaternion(b[6], b[7], b[8], b[9])), Vector3(b[3], b[4], b[5]) * s))
	var parts: Array = []
	for mk in tools:
		parts.append([(tools[mk] as SurfaceTool).commit(), _material(mk)])
	_meshes[ck] = parts
	return parts

# T182: merged boxes can't use box-local triplanar, so bake each face's planar UVs
# (metres / TEX_M, the kit's constant texel size) before the box is transformed.
static func _box(size: Vector3, off: Vector2) -> ArrayMesh:
	var bm := BoxMesh.new()
	bm.size = size
	var a := bm.get_mesh_arrays()
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uv := PackedVector2Array()
	for j in vs.size():
		var v := vs[j]
		var n := ns[j].abs()
		var p := Vector2(v.z, v.y) if n.x > 0.5 else (Vector2(v.x, v.z) if n.y > 0.5 else Vector2(v.x, v.y))
		uv.append(p / MechVisuals.TEX_M + off)
	a[Mesh.ARRAY_TEX_UV] = uv
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return am

static func _material(mk: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if mk.begins_with("E#"):  # energy tells: full-bright, like mech glow parts
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.html(mk.substr(2))
	elif _TEX.has(mk):
		m.albedo_texture = load(_TEX[mk])
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		m.roughness = 0.7
	else:
		m.albedo_color = _COLORS[mk]
		m.roughness = 0.7
	return m
