class_name ArcWeapon
extends "res://scripts/WeaponBase.gd"
# Continuous homing beam aimed at locked_target. Damage ticks at fire_rate.
# Beam pivot child rotates each tick to track target in global space.

var _beam_pivot: Node3D = null
var _beam_mesh: MeshInstance3D = null
var _loop_player: AudioStreamPlayer3D = null

func _ready() -> void:
	super._ready()
	_beam_pivot = Node3D.new()
	add_child(_beam_pivot)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.0, 1.0, 0.88)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.0, 1.0, 0.88)
	mat.emission_energy_multiplier = 5.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()  # T259: the bolt, rebuilt every frame it shows
	# B112: the colour lives on the mesh surface -- Mech's shield flash sets and then nulls
	# material_override on every torso mesh, which left a material_override bolt grey.
	_bolt_mat = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam_pivot.add_child(mi)
	_beam_mesh = mi
	_beam_mesh.visible = false

# T247 (HUMAN_FOUND_ISSUES 2026-11-05: "beam visible even when not firing"): the beam shows
# only while _do_fire keeps refreshing it. The explicit hides missed releases -- the RMB
# ("fire selected weapon") release never reaches on_fire_release, nor does a slot toggle or
# death mid-beam -- and on a client a late unreliable _rpc_beam_fx could land after the
# reliable hide. Fire rate 10/s refreshes every 0.1 s; BEAM_HOLD_S rides out a lost packet.
const BEAM_HOLD_S := 0.35
var _beam_age := 0.0

func _physics_process_impl(delta: float) -> void:
	super._physics_process_impl(delta)
	if _beam_mesh != null and _beam_mesh.visible:
		_beam_age += delta
		if _beam_age > BEAM_HOLD_S:
			_hide_beam()

# T259 (HUMAN_FOUND_ISSUES 2026-11-05 "lightning arc (continuous)"): the beam is a jagged
# bolt, pinned at the muzzle and the target and kinked most mid-way, re-drawn every frame
# while it shows; two crossed ribbons so it reads from any side without billboarding.
const BOLT_SEGS := 10
const BOLT_JITTER := 0.3  # m, widest sideways kink
const BOLT_WIDTH := 0.07
static var _bolt_rng := RandomNumberGenerator.new()  # cosmetic; keeps the global RNG untouched
var _beam_len := 1.0
var _bolt_mat: StandardMaterial3D = null
var _bolt_points := PackedVector3Array()

func _process(_delta: float) -> void:
	if _beam_mesh != null and _beam_mesh.visible:
		_redraw_bolt()

func _redraw_bolt() -> void:
	_bolt_points.resize(BOLT_SEGS + 1)
	for i in BOLT_SEGS + 1:
		var f := float(i) / BOLT_SEGS
		var j := BOLT_JITTER * sin(PI * f)
		_bolt_points[i] = Vector3(_bolt_rng.randf_range(-j, j), _bolt_rng.randf_range(-j, j), -_beam_len * f)
	var im := _beam_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _bolt_mat)
	for side: Vector3 in [Vector3(BOLT_WIDTH * 0.5, 0, 0), Vector3(0, BOLT_WIDTH * 0.5, 0)]:
		for i in BOLT_SEGS:
			var a := _bolt_points[i]
			var b := _bolt_points[i + 1]
			for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
				im.surface_add_vertex(v)
	im.surface_end()

func fire() -> void:
	if owner_mech == null or owner_mech.get("locked_target") == null:
		_hide_beam()
		return
	# T273 (HUMAN_FOUND 2026-11-05: "Arc weapon should be unable to fire until it's within
	# range"): out of range nothing is spent -- no cooldown, ammo, beam or sound.
	var t := owner_mech.get("locked_target") as Node3D
	if not is_instance_valid(t) or global_position.distance_to(t.global_position) > range:
		_hide_beam()
		return
	if max_ammo >= 0 and ammo <= 0:
		_hide_beam()
	super.fire()

func on_fire_release() -> void:
	_hide_beam()

func _hide_beam() -> void:
	# Audit #15: replicate the off-transition (guarded: _hide_beam is called
	# every no-lock tick; only broadcast when the beam was actually showing).
	if _beam_mesh.visible and multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_hide_beam.rpc()
	_beam_mesh.visible = false
	if _loop_player != null and _loop_player.playing:
		_loop_player.stop()

@rpc("authority", "reliable")
func _rpc_hide_beam() -> void:
	if multiplayer.is_server():
		return
	_hide_beam()

func _do_fire() -> void:
	if owner_mech == null:
		return
	var target := owner_mech.get("locked_target") as Node3D
	if not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) > range:
		_hide_beam()
		return

	var target_pos := target.global_position + Vector3(0, 1.0, 0)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, target_pos)
	query.exclude = owner_mech.get_exclude_rids()
	var result := space.intersect_ray(query)
	if result:
		if result.collider.has_method("take_damage"):
			var target_team: int = result.collider.get("team") if "team" in result.collider else -1
			var own_team: int = owner_mech.get("team") if "team" in owner_mech else -2
			if target_team != own_team:
				result.collider.take_damage(damage, self)
				_emit_hit_if_visible(result.collider, result.position)

	_beam_fx(target_pos)
	# Audit #15: beam + loop audio were server-only; remote peers saw nothing.
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_beam_fx.rpc(target_pos)

func _beam_fx(target_pos: Vector3) -> void:
	var dist := maxf(0.01, global_position.distance_to(target_pos))
	_beam_pivot.look_at(target_pos, Vector3.UP)
	_beam_len = dist
	_beam_age = 0.0  # T247
	var was_visible := _beam_mesh.visible
	_beam_mesh.visible = true
	if not was_visible:
		_start_arc_loop()

@rpc("authority", "unreliable_ordered")
func _rpc_beam_fx(target_pos: Vector3) -> void:
	if multiplayer.is_server():
		return
	_beam_fx(target_pos)

func _start_arc_loop() -> void:
	var stream := SoundManager.get_sfx_stream("arc_loop")
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
