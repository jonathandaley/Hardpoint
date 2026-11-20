class_name Flamer
extends "res://scripts/WeaponBase.gd"
# T457 (user 2026-11-17: "add as many mechs as you think are good. Also maps and weapons."): a flame
# cone. Each fire tick (server) every enemy inside `cone_deg` of the aim and `range`, with nothing
# in the way, takes `damage` and catches fire: `burn_dps` for `burn_s` after (Mech.ignite, refreshed
# while it stays in the flame). What a line of sight meets first takes the hit (an Everest front
# shield soaks it). REFILLING fuel: the tank (max_ammo) refills while it isn't firing. One particle
# flame per weapon on every peer (unreliable, refreshed each tick like the arc beam).

@export var cone_deg: float = 11.0   # half-angle
@export var burn_dps: float = 6.0
@export var burn_s: float = 2.0

const FLAME_HOLD_S := 0.25  # the flame shows this long after the last fire tick (a lost packet)
var _flame: CPUParticles3D
var _flame_age := 9.0

func _ready() -> void:
	super._ready()
	_flame = CPUParticles3D.new()
	_flame.amount = 40
	_flame.lifetime = 0.35
	_flame.emitting = false
	_flame.local_coords = false
	_flame.direction = Vector3(0, 0, -1)
	_flame.spread = cone_deg * 0.8
	_flame.initial_velocity_min = range / 0.35 * 0.8
	_flame.initial_velocity_max = range / 0.35
	_flame.gravity = Vector3(0, 2.0, 0)
	_flame.scale_amount_min = 0.3
	_flame.scale_amount_max = 0.5
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.3))
	grow.add_point(Vector2(1.0, 2.2))
	_flame.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.4, 0.95))
	ramp.add_point(0.4, Color(1.0, 0.45, 0.1, 0.8))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.35, 0.1, 0.05, 0.0))
	_flame.color_ramp = ramp
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	_flame.mesh = q
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)

func _physics_process_impl(delta: float) -> void:
	super._physics_process_impl(delta)
	if _flame != null and _flame.emitting:
		_flame_age += delta
		if _flame_age > FLAME_HOLD_S:
			_flame.emitting = false
			if _loop_player != null:
				_loop_player.stop()

func _show_flame() -> void:
	if _flame == null:
		return
	_flame.position = muzzle_local if muzzle_local != Vector3.ZERO else Vector3(0, 0, -0.6)
	_flame_age = 0.0
	if not _flame.emitting:
		_flame.emitting = true
		_start_loop()

var _loop_player: AudioStreamPlayer3D = null

func _start_loop() -> void:
	var stream := SoundManager.get_sfx_stream("flamer_loop")
	if stream == null:
		return
	if _loop_player == null:
		_loop_player = AudioStreamPlayer3D.new()
		_loop_player.bus = "SFX"
		_loop_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_loop_player.unit_size = 10.0
		_loop_player.max_distance = 80.0
		add_child(_loop_player)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_loop_player.stream = stream
	_loop_player.play()

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return
	_show_flame()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		rpc_fx(&"_rpc_flame_fx", [])
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	# memory feedback_weapon_aim_pattern: the camera sits ~6 m behind the gun -- aim at what the
	# camera ray hits, and measure the cone and the reach from the gun
	var space := get_world_3d().direct_space_state
	var ex: Array = owner_mech.get_exclude_rids()
	var cam_fwd := -cam.global_transform.basis.z
	var aq := PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position + cam_fwd * (range + 20.0))
	aq.exclude = ex
	var ah := space.intersect_ray(aq)
	var from := global_position
	var aim: Vector3 = ah.position if not ah.is_empty() else cam.global_position + cam_fwd * (range + 20.0)
	var fwd := (aim - from).normalized()
	var cos_cone := cos(deg_to_rad(cone_deg))
	var own_team: int = owner_mech.get("team")
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == owner_mech or m.get("team") == own_team or m.get("is_dead") or float(m.get("health")) <= 0.0:
			continue
		var c: Vector3 = (m as Node3D).global_position + Vector3.UP * 1.2 * (m as Node3D).scale.y
		var to := c - from
		var d := to.length()
		if d > range or d < 0.01 or to.normalized().dot(fwd) < cos_cone:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, c)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		_hit(hit, damage)
		if _owner_of(hit.collider) == m and m.has_method("ignite"):
			m.call("ignite", burn_s, burn_dps, self)

static func _owner_of(n: Node) -> Node:
	while n != null and not n.is_in_group("mechs"):
		n = n.get_parent()
	return n

@rpc("authority", "unreliable_ordered")
func _rpc_flame_fx() -> void:
	if not is_inside_tree() or multiplayer.is_server():  # V50 / B130
		return
	_show_flame()

func damage_text() -> String:  # T538
	return "%s a tick  + burn %s /s for %s s" % [num(damage), num(burn_dps), num(burn_s)]
