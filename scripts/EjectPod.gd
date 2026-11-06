extends Node3D
# T267 (HUMAN_FOUND 2026-11-05 "bots should eject on death like players"; user 2026-11-05: "death
# explosion launches a rocket canister skyward at a slight curved angle, leaving a trail of
# smoke"): every destroyed mech fires its pilot's canister on every peer (cosmetic; the death
# itself is replicated). It boosts for BOOST_S with a sideways push that bends the climb, then
# coasts over under gravity and is freed after LIFE_S. Script-driven, not a RigidBody: nothing
# for it to collide with.

const BOOST_S := 0.9
const BOOST_ACC := 30.0  # m/s^2 up while the motor burns
const LIFE_S := 6.0

var vel := Vector3.ZERO
var drift := Vector3.ZERO  # sideways acceleration while boosting: the curve
var age := 0.0
var _puff_t := 0.0
static var _puff_mesh: SphereMesh = null
const PUFF_EVERY := 0.035  # s: a puff left behind this often while the trail runs
const PUFF_LIFE := 1.2
var _flame: MeshInstance3D = null

func launch(from: Vector3, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var side := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
	vel = Vector3.UP * 14.0 + side * 1.5
	drift = side * rng.randf_range(5.0, 8.0)
	global_position = from

func _ready() -> void:
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.22
	cyl.bottom_radius = 0.28
	cyl.height = 0.9
	body.mesh = cyl
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.22, 0.24, 0.27)
	metal.roughness = 0.6
	body.material_override = metal
	add_child(body)
	var band := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.255
	bm.bottom_radius = 0.265
	bm.height = 0.12
	band.mesh = bm
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.45, 0.1)
	orange.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	band.material_override = orange
	band.position.y = 0.2
	add_child(band)
	_flame = MeshInstance3D.new()  # motor glow under the canister
	var fm := SphereMesh.new()
	fm.radius = 0.2
	fm.height = 0.5
	_flame.mesh = fm
	var hot := StandardMaterial3D.new()
	hot.albedo_color = Color(1.0, 0.75, 0.3)
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame.material_override = hot
	_flame.position.y = -0.6
	add_child(_flame)

func _process(delta: float) -> void:
	age += delta
	var boosting := age < BOOST_S
	vel += ((Vector3.UP * BOOST_ACC + drift) if boosting else Vector3(0, -9.8, 0)) * delta
	global_position += vel * delta
	if vel.length() > 0.1 and vel.normalized().dot(Vector3.UP) > -0.999:  # points along its flight
		global_transform.basis = Basis(Quaternion(Vector3.UP, vel.normalized()))
	_flame.visible = boosting
	if age < BOOST_S + 0.5:  # the smoke trail: puffs left in the world, swelling and fading
		_puff_t += delta
		while _puff_t >= PUFF_EVERY:
			_puff_t -= PUFF_EVERY
			_puff(global_transform * Vector3(0, -0.6, 0))
	if age > LIFE_S:
		queue_free()

func _puff(at: Vector3) -> void:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 0.3
		_puff_mesh.height = 0.6
		_puff_mesh.radial_segments = 8
		_puff_mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.85, 0.85, 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = _puff_mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(mi)
	mi.global_position = at
	var tw := mi.create_tween().set_parallel()
	tw.tween_property(mi, "scale", Vector3.ONE * 2.6, PUFF_LIFE)
	tw.tween_property(mat, "albedo_color:a", 0.0, PUFF_LIFE)
	tw.chain().tween_callback(mi.queue_free)

