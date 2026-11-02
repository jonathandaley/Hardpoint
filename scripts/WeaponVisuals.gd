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
const _COLORS := {
	"A": Color(0.216, 0.231, 0.267),   # weapon-steel-armor.png average (#373b44)
	"D": Color(0.122, 0.133, 0.165),   # weapon-steel-detail.png average (#1f222a)
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

static func apply(weapon: Node3D) -> void:
	var key := kit_name(weapon.scene_file_path)
	if not WeaponKit.DATA.has(key):
		return
	for c in weapon.get_children():
		if c is MeshInstance3D:  # placeholder geometry only (no script reads these nodes)
			weapon.remove_child(c)
			c.free()
	var heavy: bool = int(weapon.get("slot_size")) == 1
	for part in _parts(key, HEAVY_SCALE if heavy else LIGHT_SCALE):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.set_surface_override_material(0, part[1])
		weapon.add_child(mi)

static func _parts(key: String, s: float) -> Array:
	var ck := "%s@%s" % [key, s]
	if _meshes.has(ck):
		return _meshes[ck]
	var tools := {}
	for b in WeaponKit.DATA[key]:
		var st: SurfaceTool = tools.get(b[10])
		if st == null:
			st = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[b[10]] = st
		var bm := BoxMesh.new()
		bm.size = Vector3(b[0], b[1], b[2]) * s
		st.append_from(bm, 0, Transform3D(Basis(Quaternion(b[6], b[7], b[8], b[9])), Vector3(b[3], b[4], b[5]) * s))
	var parts: Array = []
	for mk in tools:
		parts.append([(tools[mk] as SurfaceTool).commit(), _material(mk)])
	_meshes[ck] = parts
	return parts

static func _material(mk: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if mk.begins_with("E#"):  # energy tells: full-bright, like mech glow parts
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.html(mk.substr(2))
	else:
		m.albedo_color = _COLORS.get(mk, _COLORS["A"])
		m.roughness = 0.7
	return m
