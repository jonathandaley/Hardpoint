extends MeshInstance3D
# T193 (user 2026-11-02: blob shadows, vanilla-Minecraft style): a soft dark disc on the
# ground under its parent mech, used when Settings -> Shadows is BLOB (the sun casts no
# shadows then). Follows the mech in plan view, lies on whatever is below it, shrinks and
# fades with height (jumps), hides with the mech (death) and while it is stealthed.

const MAX_DROP := 12.0  # m below the mech's feet that still gets a shadow
const FADE_H := 8.0     # m of height over which the disc shrinks/fades to its minimum

var radius := 1.0

static var _mat: StandardMaterial3D

func _ready() -> void:
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	mesh = q
	material_override = _material()

static func _material() -> StandardMaterial3D:
	if _mat == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.55))
		g.set_color(1, Color(0, 0, 0, 0))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		tex.width = 64
		tex.height = 64
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_texture = tex
	return _mat

func _process(_delta: float) -> void:
	var m := get_parent() as Node3D
	if m == null or not m.visible or m.get("is_stealthy"):
		visible = false
		return
	var from := m.global_position + Vector3.UP * 0.5
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * (MAX_DROP + 0.5), 1)
	q.exclude = [(m as CollisionObject3D).get_rid()] if m is CollisionObject3D else []
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		visible = false
		return
	var n: Vector3 = hit.normal
	var x := n.cross(Vector3.FORWARD) if absf(n.dot(Vector3.FORWARD)) < 0.99 else Vector3.RIGHT
	x = x.normalized()
	var k := clampf(1.0 - (m.global_position.y - hit.position.y) / FADE_H, 0.3, 1.0)
	visible = true
	var d := 2.0 * radius * k
	global_transform = Transform3D(Basis(x * d, n, x.cross(n) * d), hit.position + n * 0.04)
	transparency = 1.0 - k
