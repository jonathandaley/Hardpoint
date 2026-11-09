class_name MachineGun
extends "res://scripts/ProjectileGun.gd"
# Fixed mag, accelerating fire rate while trigger held, resets on release.
# base_fire_rate -> ramps to max_fire_rate at rate_accel rps/s.
# Releasing trigger decays back to base at rate_decay rps/s.

@export var spread_angle: float = 1.0  # half-cone degrees; total spread = 2x this
@export var base_fire_rate: float = 4.0
@export var max_fire_rate: float = 14.0
@export var rate_accel: float = 10.0   # rps added per second while held
@export var rate_decay: float = 25.0   # rps lost per second after release

var _current_rate: float = 0.0
var _trigger_held: bool = false
var _loop_player: AudioStreamPlayer3D = null

func _do_fire() -> void:
	if owner_mech == null:
		return
	var cam := owner_mech.get("camera") as Camera3D
	if cam == null:
		return
	var cam_fwd := -cam.global_transform.basis.z
	if spread_angle > 0.0:
		var perp := Vector3(Game.rng.randf_range(-1.0, 1.0), Game.rng.randf_range(-1.0, 1.0), Game.rng.randf_range(-1.0, 1.0))
		perp = perp - cam_fwd * perp.dot(cam_fwd)
		if perp.length_squared() > 0.0001:
			cam_fwd = (cam_fwd + perp.normalized() * tan(deg_to_rad(spread_angle))).normalized()
	var space := get_world_3d().direct_space_state
	var aim_query := PhysicsRayQueryParameters3D.create(
		cam.global_position, cam.global_position + cam_fwd * range)
	aim_query.exclude = owner_mech.get_exclude_rids()
	var aim_result := space.intersect_ray(aim_query)
	var aim_point: Vector3 = aim_result.position if aim_result \
		else cam.global_position + cam_fwd * range
	if (aim_point - global_position).dot(cam_fwd) <= 0.0:
		aim_point = global_position + cam_fwd * range
	var proj := PROJECTILE_SCENE.instantiate() as Projectile
	proj.damage = damage
	proj.speed = projectile_speed
	proj.lifetime = range / projectile_speed
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.source_weapon = self
	proj.on_hit = func(body, pos): _emit_hit_if_visible(body, pos, true)
	get_tree().current_scene.add_child(proj)
	proj.global_transform = Transform3D(Basis(), global_position).looking_at(aim_point)
	VFX.casing(self)  # T263
	# B110: this override skipped ProjectileGun's T100 ghost send, so clients never saw MG rounds.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_spawn_ghost.rpc(global_position, proj.global_transform.basis,
			proj.speed, proj.lifetime, proj.team)

func _ready() -> void:
	super._ready()
	_current_rate = base_fire_rate

# Ramp state lives on the physics side: fire() (called from Mech._physics_process
# every tick while the trigger is held) sets _trigger_held, and this consumes and
# clears it once per physics tick. Keeping both ends at physics rate makes the
# ramp independent of render frame rate.
func _physics_process(delta: float) -> void:
	super._physics_process(delta)  # base cooldown/reload/refill timers
	if _trigger_held or _remote_firing:  # T262: a client ramps from the loop on/off RPC
		_current_rate = minf(_current_rate + rate_accel * delta, max_fire_rate)
	else:
		_current_rate = maxf(_current_rate - rate_decay * delta, base_fire_rate)
	_trigger_held = false

func _process(_delta: float) -> void:
	if _reloading and _loop_player != null and _loop_player.playing:
		_loop_player.stop()
		_bc_loop(false)
	_update_barrel_glow()

# T262 (HUMAN_FOUND_ISSUES 2026-11-05: "barrel should start glowing as ramp-up increases,
# red-hot at max speed"): an additive shell over the kit barrel + muzzle (boxes 20/21 of
# WeaponKit "MachineGun", same scale as WeaponVisuals.apply) from dull red to red-hot as
# the fire rate climbs, fading as it cools. Clients have no fire() calls, so they ramp
# _current_rate from the replicated loop on/off instead (_remote_firing).
const GLOW_BOXES := [[Vector3(0.14, 0.14, 0.73), Vector3(0, 0.02, -0.86)], [Vector3(0.18, 0.18, 0.15), Vector3(0, 0.02, -1.24)]]
const GLOW_COOL := Color(0.45, 0.03, 0.0)
const GLOW_HOT := Color(1.0, 0.32, 0.08)
var _remote_firing := false
var _glow: MeshInstance3D = null
var _glow_mat: StandardMaterial3D = null

func get_heat() -> float:
	return clampf((_current_rate - base_fire_rate) / maxf(max_fire_rate - base_fire_rate, 0.001), 0.0, 1.0)

func _update_barrel_glow() -> void:
	var h := get_heat()
	if _glow == null:
		if h <= 0.02:
			return
		var s := (0.8 if slot_size == 1 else 0.5) * visual_scale
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for b in GLOW_BOXES:
			var box := BoxMesh.new()
			box.size = (b[0] as Vector3) * s * 1.04
			st.append_from(box, 0, Transform3D(Basis(), (b[1] as Vector3) * s))
		_glow_mat = StandardMaterial3D.new()
		_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		st.set_material(_glow_mat)  # on the surface: Mech's shield flash nulls material_override (B112)
		_glow = MeshInstance3D.new()
		_glow.name = "BarrelGlow"
		_glow.mesh = st.commit()
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_glow)
	_glow.visible = h > 0.02
	var c := GLOW_COOL.lerp(GLOW_HOT, h) * h  # additive: scaling rgb fades it in
	c.a = 1.0
	_glow_mat.albedo_color = c

func _start_mg_loop() -> void:
	var stream := SoundManager.get_sfx_stream("machinegun_fire")
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
	if not _loop_player.playing:
		_loop_player.stream = stream
		_loop_player.play()

func on_fire_release() -> void:
	if _loop_player != null and _loop_player.playing:
		_loop_player.stop()
	_bc_loop(false)

# Audit #10: the fire-sound loop player is local to the server, so remote peers
# heard nothing from machine guns. Replicate loop on/off transitions (reliable:
# transitions are rare and a lost "off" would loop forever on the client).
var _loop_on_remote: bool = false

func _bc_loop(on: bool) -> void:
	if not (multiplayer.has_multiplayer_peer() and multiplayer.is_server()):
		return
	if on == _loop_on_remote:
		return
	_loop_on_remote = on
	_rpc_mg_loop.rpc(on)

@rpc("authority", "reliable")
func _rpc_mg_loop(on: bool) -> void:
	if multiplayer.is_server():
		return
	_remote_firing = on  # T262
	if on:
		_start_mg_loop()
	elif _loop_player != null and _loop_player.playing:
		_loop_player.stop()

func fire() -> void:
	_trigger_held = true
	if _cooldown > 0.0:
		return
	if _reloading:
		return
	if max_ammo >= 0 and ammo <= 0:
		if magazine_type == MagazineType.FIXED:
			_start_reload()
		return
	_cooldown = 1.0 / _current_rate
	_start_mg_loop()
	_bc_loop(true)
	_do_fire()
	if muzzle_flash_enabled:
		# Audit #10: this override dropped the broadcast flag WeaponBase.fire()
		# passes, so remote peers never saw MG muzzle flashes.
		var _bc: bool = multiplayer.has_multiplayer_peer() and multiplayer.is_server()
		_muzzle_flash(_bc)
	if shake_magnitude > 0.0 and owner_mech != null and owner_mech.has_method("apply_camera_shake"):
		owner_mech.apply_camera_shake(shake_magnitude)
	if max_ammo >= 0:
		ammo -= 1
		if ammo <= 0 and magazine_type == MagazineType.FIXED:
			_start_reload()
