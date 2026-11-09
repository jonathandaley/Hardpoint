extends MultiMeshInstance3D
# T263 (HUMAN_FOUND 2026-11-05: spent shells "should stick around longer, at least at higher
# graphics settings"; user 2026-11-08: build real casings, none for Patience, two bounces):
# every spent casing in the arena is one instance of ONE MultiMesh -- one draw call however many
# lie around, no node or physics body per casing. Scripted motion: ejected to the gun's right,
# gravity, two bounces that lose most of their height, a tumble that slows, a short roll onto its
# side, then rest. Landing height comes from one downward ray at the predicted landing spot
# (slopes, steps, off ledges). Only airborne casings update. The pool is a ring: `cap` (GRAPHICS >
# LONG-LASTING CASINGS) decides how long they stay -- the oldest is reused when it's full.
# Cosmetic and local on every peer (VFX.casing, called where each shot / shot ghost spawns).

const GRAVITY := 14.0
const BOUNCES := 2
const BOUNCE_KEEP := 0.45  # vertical speed kept per bounce: ~20% of the height
const ROLL_S := 0.3
const LAND_GUESS_S := 0.55  # flight time used to guess where the casing comes down
const BRASS := Color(0.86, 0.64, 0.24)
const SHELL := Color(0.72, 0.1, 0.08)  # shotgun shells
const SIZE := Vector3(0.06, 0.06, 0.17)  # mech-scale; heavy guns x1.4

var cap := 1000

var _next := 0
var _used := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _axis := PackedVector3Array()
var _rot: Array[Quaternion] = []
var _scale := PackedFloat32Array()
var _ground := PackedFloat32Array()
var _rate := PackedFloat32Array()
var _bounce := PackedInt32Array()
var _roll := PackedFloat32Array()
var _air: Array[int] = []  # instances still moving
var _rng := RandomNumberGenerator.new()  # cosmetic; the gameplay RNG stays untouched

func _ready() -> void:
	name = "Casings"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var box := BoxMesh.new()
	box.size = SIZE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.6
	mat.roughness = 0.45
	box.material = mat
	mm.mesh = box
	mm.instance_count = cap
	mm.visible_instance_count = 0
	multimesh = mm
	_pos.resize(cap)
	_vel.resize(cap)
	_axis.resize(cap)
	_rot.resize(cap)
	_scale.resize(cap)
	_ground.resize(cap)
	_rate.resize(cap)
	_roll.resize(cap)
	_bounce.resize(cap)

# T337 (user 2026-11-08: shells shot through the body of mechs that hold their guns from behind;
# picked "eject from mid-gun"): the casing leaves the gun's receiver, RECEIVER_K of the way from the
# gun's origin (its back end on those mechs, inside the shoulder block) to the kit model's muzzle.
const RECEIVER_K := 0.45

## Casing size factor for `weapon` (heavy guns x1.4, the gun's own scale).
static func casing_scale(weapon: Node3D) -> float:
	var heavy: bool = int(weapon.get("slot_size")) == 1 if weapon.get("slot_size") != null else false
	return (1.4 if heavy else 1.0) * clampf(weapon.global_transform.basis.get_scale().x, 0.5, 2.0)

## Which way casings fly sideways: outward -- a gun on the mech's left throws them to its left
## (a casing thrown right from there crossed the whole torso); centre and right guns to the right.
static func side(weapon: Node3D) -> float:
	var m = weapon.get("owner_mech")
	if m == null or not is_instance_valid(m) or not (m is Node3D):
		return 1.0
	return -1.0 if (m as Node3D).to_local(weapon.global_position).x < -0.05 else 1.0

## A centre-line gun (Hippogriff's under the chest plate, Vesuvius's on top) throws its casings
## lower and shorter: thrown like a shoulder gun's they flew up into the plate / across onto the
## shoulder block.
static func centre(weapon: Node3D) -> bool:
	var m = weapon.get("owner_mech")
	return m != null and is_instance_valid(m) and m is Node3D and absf((m as Node3D).to_local(weapon.global_position).x) <= 0.05

## A casing's launch velocity from `weapon`: outward, up, a bit back. `jitter` 0..1 picks across
## the spread (0.5 = the mean, what the clearance probe checks).
static func launch(weapon: Node3D, jitter_side: float, jitter_up: float, back: float) -> Vector3:
	var b := weapon.global_transform.basis
	var c := 0.55 if centre(weapon) else 1.0
	var u := 0.35 if centre(weapon) else 1.0
	return b.x.normalized() * side(weapon) * lerpf(2.5, 4.0, jitter_side) * c \
		+ b.y.normalized() * lerpf(2.0, 3.5, jitter_up) * u + b.z.normalized() * back

## Where a casing leaves `weapon` (world space).
static func port(weapon: Node3D) -> Vector3:
	var b := weapon.global_transform.basis
	var s := casing_scale(weapon)
	var mz = weapon.get("muzzle_local")
	var base := weapon.to_global(mz * RECEIVER_K) if mz is Vector3 and mz != Vector3.ZERO else weapon.global_position
	return base + b.x.normalized() * 0.12 * s * side(weapon) + b.y.normalized() * 0.05 * s

## One casing out of `weapon` (shell = a shotgun shell).
func eject(weapon: Node3D, shell := false) -> void:
	var b := weapon.global_transform.basis
	var s := casing_scale(weapon)
	var p := port(weapon)
	var v := launch(weapon, _rng.randf(), _rng.randf(), _rng.randf_range(0.0, 1.0))
	var i := _next
	_next = (_next + 1) % cap
	_used = mini(_used + 1, cap)
	multimesh.visible_instance_count = _used
	_pos[i] = p
	_vel[i] = v
	_axis[i] = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)).normalized()
	_rot[i] = Quaternion(b.orthonormalized())
	_scale[i] = s
	_rate[i] = _rng.randf_range(14.0, 24.0)
	_bounce[i] = 0
	_roll[i] = 0.0
	_ground[i] = _landing_y(p, v, weapon)
	multimesh.set_instance_color(i, SHELL if shell else BRASS)
	if not _air.has(i):
		_air.append(i)
	_write(i)

func _landing_y(p: Vector3, v: Vector3, weapon: Node3D) -> float:
	var land := p + Vector3(v.x, 0.0, v.z) * LAND_GUESS_S
	var q := PhysicsRayQueryParameters3D.create(Vector3(land.x, p.y + 0.5, land.z), Vector3(land.x, p.y - 40.0, land.z))
	var owner_mech = weapon.get("owner_mech")
	if owner_mech != null and is_instance_valid(owner_mech) and owner_mech.has_method("get_exclude_rids"):
		q.exclude = owner_mech.get_exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if hit else p.y - 40.0  # nothing below: it falls out of sight

func _process(delta: float) -> void:
	if _air.is_empty():
		return
	var still: Array[int] = []
	for i in _air:
		var half := SIZE.x * 0.5 * _scale[i]
		if _roll[i] <= 0.0:  # in the air
			var v := _vel[i]
			v.y -= GRAVITY * delta
			var p := _pos[i] + v * delta
			_rot[i] = (_rot[i] * Quaternion(_axis[i], _rate[i] * delta)).normalized()
			if p.y <= _ground[i] + half and v.y < 0.0:
				p.y = _ground[i] + half
				_bounce[i] += 1
				if _bounce[i] > BOUNCES:
					v = Vector3(v.x, 0.0, v.z) * 0.5
					_roll[i] = ROLL_S
				else:
					v = Vector3(v.x * 0.6, -v.y * BOUNCE_KEEP, v.z * 0.6)
					_rate[i] *= 0.5
			_vel[i] = v
			_pos[i] = p
			still.append(i)
		else:  # rolling onto its side, then rest
			_roll[i] -= delta
			var v := _vel[i] * maxf(0.0, 1.0 - 6.0 * delta)
			_vel[i] = v
			_pos[i] += v * delta
			var flat := Vector3(v.x, 0.0, v.z)
			if flat.length_squared() < 0.0001:
				flat = _rot[i] * Vector3.FORWARD
				flat.y = 0.0
			if flat.length_squared() > 0.0001:
				var lie := Quaternion(Basis.looking_at(flat.normalized(), Vector3.UP))
				_rot[i] = _rot[i].slerp(lie, minf(1.0, 12.0 * delta))
			if _roll[i] > 0.0:
				still.append(i)
		_write(i)
	_air = still

func _write(i: int) -> void:
	multimesh.set_instance_transform(i, Transform3D(Basis(_rot[i]).scaled(Vector3.ONE * _scale[i]), _pos[i]))

func airborne() -> int:
	return _air.size()

func used() -> int:
	return _used
