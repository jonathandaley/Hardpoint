class_name Mech
extends CharacterBody3D

const ProjectileGun = preload("res://scripts/ProjectileGun.gd")
const MachineGun    = preload("res://scripts/MachineGun.gd")
# The Pawn. Handles movement and weapon firing.
# Ignorant of who pilots it - all control comes through InputSource.
#
# Node hierarchy:
#   Mech (CharacterBody3D)
#     Legs (Node3D)         ← rotates toward velocity direction
#       LegMesh
#     Torso (Node3D)        ← rotates with mouse look
#       BodyMesh
#       HardpointLeft / HardpointRight
#       CameraArm / Camera3D
#     CollisionShape3D

signal died
signal damaged
signal mark_requested(pos: Vector3)

@export var base_walk_speed: float = 3.15
@export var base_reload_rate: float = 1.0
@export var max_health: float = 500.0
@export var team: int = 0
@export var turn_acceleration: float = 60.0   # m/s² per axis - velocity direction change rate
@export var leg_rotation_speed: float = 15.0  # rad/s - leg visual tracking speed

var owner_peer_id: int = 0
var health: float = 0.0
var damage_taken_total: float = 0.0
var is_stealthy: bool = false
var invincible: bool = false
var _modifiers: Dictionary = {}
var _input_source: Node = null   # InputSource - untyped to avoid cache dependency
var _abilities: Array = []
var _ability_cooldowns: Dictionary = {}
var _ability_active_timers: Dictionary = {}
var _camera_pitch: float = -0.3  # matches CameraArm initial rotation.x
var _desired_move_dir: Vector3 = Vector3.ZERO
var _no_damage_timer: float = 0.0  # seconds since last damage hit; drives repair_rate skill
var _net_input_tick: int = 0       # increments every physics tick; used for 30Hz throttle
var _net_input_seq: int = 0        # monotonic send counter
var _net_look_accum: Vector2 = Vector2.ZERO  # accumulated between RPC sends (get_look_delta drains on read)
var _rpc_rate_times: Array = []    # server-side sliding window of _rpc_input arrival times (1s)
var _rpc_rate_warned: bool = false # true while peer is over 60Hz limit (suppress repeat warnings)
var _snap_buf: Array = []          # V37: last 2 server snapshots [{time,pos,quat,vel}]; T120 reads for interp

@onready var torso: Node3D = $Torso
@onready var legs: Node3D = $Legs
@onready var camera: Camera3D = $Torso/CameraArm/Camera3D
@onready var camera_arm: SpringArm3D = $Torso/CameraArm
@onready var _shield := $Torso/PhysicalShield
@onready var _energy_shield: Node = $EnergyShield

var is_dead: bool = false
var _body_meshes: Array = []
var _flash_mat: StandardMaterial3D = null
var _flash_timer_es: float = 0.0
const _ES_FLASH_DUR := 0.12
var _stealth_saved_mats: Dictionary = {}  # MeshInstance3D -> original material

var _weapons: Array = []
var _ammo_synced: Array = []   # last ammo value broadcast per slot (server, MP only)
var _active_set: Array = []  # parallel bool array; true = included in right-click subset
var _was_firing_primary: bool = false

var locked_target: Node3D = null
var lock_progress: float = 0.0
var lock_eligible: bool = false
var lock_eligible_target: Node3D = null
var _lock_candidate: Node3D = null
var _lock_timer: float = 0.0
var _lock_time: float = 3.0

const _SHAKE_DURATION := 0.15
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0

var walk_speed: float:
	get: return base_walk_speed * _modifiers.get("walk_speed", 1.0)

func _ready() -> void:
	add_to_group("mechs")
	health = max_health
	_setup_weapon_owners()
	_build_weapon_list()
	_body_meshes = torso.find_children("*", "MeshInstance3D", true, false)

func _process(delta: float) -> void:
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		var frac := _shake_timer / _SHAKE_DURATION
		camera_arm.rotation.x = _camera_pitch + randf_range(-_shake_intensity, _shake_intensity) * frac
	else:
		camera_arm.rotation.x = _camera_pitch
	if _flash_timer_es > 0.0:
		_flash_timer_es = maxf(0.0, _flash_timer_es - delta)
		if _flash_timer_es == 0.0:
			for mesh in _body_meshes:
				mesh.material_override = null
	if _input_source != null and _input_source.has_method("is_human_input") and _input_source.is_human_input():
		_no_damage_timer += delta
		var repair_eff: float = Game.get_skill_effect("repair_rate")
		if _no_damage_timer >= 3.0 and repair_eff > 0.0 and health > 0.0:
			health = minf(health + repair_eff * delta, max_health)

func apply_camera_shake(magnitude: float) -> void:
	_shake_intensity = magnitude
	_shake_timer = _SHAKE_DURATION

func configure_energy_shield(has_shield: bool, max_hp: float, regen_rate: float, regen_delay: float) -> void:
	if not has_shield:
		return
	_energy_shield.call("activate", max_hp, regen_rate, regen_delay)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(0.3, 0.8, 1.0)
	_flash_mat.emission_enabled = true
	_flash_mat.emission = Color(0.3, 0.8, 1.0)
	_flash_mat.emission_energy_multiplier = 2.0

func configure_shield(has_shield: bool, max_hp: float = 300.0) -> void:
	if has_shield:
		_shield.activate(max_hp)
	# disabled by default in scene; no action needed for mechs without shields

func apply_pilot_skills() -> void:
	max_health      *= 1.0 + Game.get_skill_effect("health")
	health           = max_health
	base_walk_speed *= 1.0 + Game.get_skill_effect("move_speed")
	_lock_time      *= maxf(0.1, 1.0 - Game.get_skill_effect("lock_speed"))
	var dmg_eff:    float = Game.get_skill_effect("damage")
	var spd_eff:    float = Game.get_skill_effect("projectile_speed")
	var rl_eff:     float = Game.get_skill_effect("reload_speed")
	var spread_eff: float = Game.get_skill_effect("spread_reduction")
	for weapon in _weapons:
		if not is_instance_valid(weapon):
			continue
		weapon.damage *= 1.0 + dmg_eff
		if weapon is ProjectileGun:
			weapon.projectile_speed *= 1.0 + spd_eff
			weapon.reload_time       = maxf(0.1, weapon.reload_time * (1.0 - rl_eff))
			weapon.inaccuracy_angle *= maxf(0.0, 1.0 - spread_eff)
			if weapon is MachineGun:
				weapon.spread_angle *= maxf(0.0, 1.0 - spread_eff)
	if is_instance_valid(_energy_shield) and _energy_shield.get("_active") == true:
		_energy_shield.max_shield_hp *= 1.0 + Game.get_skill_effect("shield_capacity")
		_energy_shield.shield_hp      = _energy_shield.max_shield_hp

func has_lock_weapon() -> bool:
	for w in _weapons:
		if is_instance_valid(w) and w.get("requires_lock") == true:
			return true
	return false

func get_exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_shield) and _shield.visible:
		rids.append(_shield.get_rid())
	return rids

func configure_weapons(slots: Array) -> void:
	if slots.is_empty():
		return
	for child in torso.get_children():
		if child.name.begins_with("Hardpoint"):
			child.queue_free()
	for i in slots.size():
		var slot = slots[i]
		var scene: PackedScene = slot.weapon_scene
		if scene == null:
			continue
		var weapon: Node = scene.instantiate()
		var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0
		var w_size: int = int(weapon.get("slot_size")) if "slot_size" in weapon else 0
		if s_size != w_size:
			push_warning("[Mech] slot %d size mismatch (slot=%d weapon=%d) -- skipped" % [i, s_size, w_size])
			weapon.queue_free()
			continue
		var hp := Node3D.new()
		hp.name = "Hardpoint%d" % i
		hp.position = slot.position
		torso.add_child(hp)
		if "owner_mech" in weapon:
			weapon.owner_mech = self
		hp.add_child(weapon)
	_build_weapon_list()
	_body_meshes = torso.find_children("*", "MeshInstance3D", true, false)

func configure_legs(hip_sweep: float, bob_magnitude: float, cycle_rate: float) -> void:
	legs.set("hip_sweep_amount", hip_sweep)
	legs.set("bob_magnitude", bob_magnitude)
	legs.set("cycle_rate", cycle_rate)

func configure_abilities(abilities: Array) -> void:
	_abilities = abilities
	_ability_cooldowns.clear()
	_ability_active_timers.clear()
	is_stealthy = false
	for ability in abilities:
		var key: String = ability.effect_key
		if ability.trigger == 1:
			_apply_passive(key)
		else:
			_ability_cooldowns[key] = 0.0
			if ability.duration > 0.0:
				_ability_active_timers[key] = 0.0

func _apply_passive(key: String) -> void:
	if key == "stealth":
		is_stealthy = true

func _get_hardpoints() -> Array:
	var hps: Array = []
	for child in torso.get_children():
		if child.name.begins_with("Hardpoint"):
			hps.append(child)
	return hps

func _build_weapon_list() -> void:
	_weapons.clear()
	for hp in _get_hardpoints():
		for child in hp.get_children():
			if child.has_method("fire"):
				_weapons.append(child)
	_active_set.resize(_weapons.size())
	_active_set.fill(true)
	_ammo_synced.clear()
	for w in _weapons:
		_ammo_synced.append(w.get("ammo"))

func get_weapons() -> Array:
	return _weapons

func get_active_set() -> Array:
	return _active_set.duplicate()

func toggle_weapon_slot(idx: int) -> void:
	if idx >= 0 and idx < _active_set.size():
		_active_set[idx] = not _active_set[idx]

func _setup_weapon_owners() -> void:
	for hp in _get_hardpoints():
		for child in hp.get_children():
			if "owner_mech" in child:
				child.owner_mech = self

# Returns the torso's world-space basis - use this for aim direction and
# for decomposing world vectors into mech-local movement axes.
func get_aim_basis() -> Basis:
	return torso.global_transform.basis

# T95: weapon fire chokepoint; MP @rpc will wrap here in T100.
func fire_weapon(slot: int, aim: Vector3 = Vector3.ZERO) -> void:
	if slot < 0 or slot >= _weapons.size() or not is_instance_valid(_weapons[slot]):
		return
	_weapons[slot].fire()
	# M1.3: autodebug event stream (no-op unless --sync-log). Fire-attempt, not
	# guaranteed shot (weapon may be on cooldown/reloading); kept uniform across
	# all weapon types by emitting at the single fire chokepoint.
	Game.sync_log_event("fired", name, {"slot": slot})

# Public entry point. Weapons always call this; never call _apply_damage directly.
# SP: runs directly. MP client: routes to server via RPC (peer_id 1).
# `source` is the weapon node that produced the damage; needed for server clamp (V32).
func take_damage(amount: float, source: Node3D = null) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var src_path: NodePath = source.get_path() if is_instance_valid(source) else NodePath()
		rpc_id(1, &"_take_damage_rpc", amount, src_path)
		return
	request_damage(amount, source)

# Server-side RPC receiver for damage (T40: validate amount server-side before applying).
@rpc("any_peer", "reliable")
func _take_damage_rpc(amount: float, src_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if not Game.mp_lobby["peers"].has(sender):
		push_error("[Mech] _take_damage_rpc: unknown sender %d" % sender)
		return
	var source: Node3D = null
	if not src_path.is_empty():
		var n := get_node_or_null(src_path)
		if n is Node3D:
			source = n
	request_damage(amount, source)

# T96: damage chokepoint; T103 will add server-side validation here.
func request_damage(amount: float, source: Node3D = null) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and source != null:
		var max_dmg: float = source.get("damage") if "damage" in source else amount
		var src_range: float = source.get("range") if "range" in source else INF
		if amount > max_dmg * 1.5:
			return
		if is_instance_valid(source) and source is Node3D:
			var dist: float = (source as Node3D).global_position.distance_to(global_position)
			if dist > src_range * 1.2:
				return
	_apply_damage(amount, source)

func _apply_damage(amount: float, source: Node3D = null) -> void:
	if health <= 0.0 or invincible:
		return
	var actual := amount
	if _energy_shield != null:
		var overflow: float = _energy_shield.call("absorb", amount)
		if overflow < amount:
			_do_shield_flash()
			if multiplayer.has_multiplayer_peer():
				_sync_shield.rpc(_energy_shield.shield_hp)
		actual = overflow
	if actual <= 0.0:
		return
	health -= actual
	_no_damage_timer = 0.0
	damage_taken_total += actual
	damaged.emit()
	SoundManager.play_sfx("damage_hit", global_position)
	print("[Mech] %s  %.0f / %.0f HP" % [name, health, max_health])
	# M1.3: autodebug event stream. Runs at the server-authoritative damage
	# chokepoint (clients route take_damage -> server via RPC), so hit/died are
	# logged once, on the authoritative peer.
	# M2.1: attribute the shooter. `source` is the weapon node (child of the
	# owning mech), so walk up to the mech for name + team; -1/"" when unknown
	# (source freed, or SP paths that pass null).
	var src_name := ""
	var src_team: int = -1
	if Game.sync_logging_enabled and source != null and is_instance_valid(source):
		var p: Node = source
		while p != null and not p.is_in_group("mechs"):
			p = p.get_parent()
		if p != null:
			src_name = p.name
			src_team = p.get("team")
	Game.sync_log_event("hit", name, {"amount": snappedf(actual, 0.01), "hp": snappedf(health, 0.01), "src": src_name, "src_team": src_team})
	if health <= 0.0:
		health = 0.0
		Game.sync_log_event("died", name, {})
		_die()
		# Audit #11: death must not ride the unreliable _sync_health stream (final
		# packet droppable) -- and clients never ran _die() at all, so dead mechs
		# stayed visible and the client-side squad picker / spectate (T127/T128,
		# both driven by `died`) never triggered. Reliable death RPC fixes all three.
		if multiplayer.has_multiplayer_peer():
			_sync_death.rpc()
	# T40: broadcast health to clients after mutation.
	if multiplayer.has_multiplayer_peer():
		_sync_health.rpc(health)

# T40: clients receive health updates here (death arrives via _sync_death, reliable).
@rpc("authority", "unreliable_ordered")
func _sync_health(h: float) -> void:
	health = h

# Audit #11: reliable death replication. Runs the same _die() path as the server:
# hides the body, disables collision, plays death SFX/VFX, emits `died` (which
# drives the client-side squad picker T127 / spectate T128), and launches the
# cockpit pod for the local player's own mech.
@rpc("authority", "reliable")
func _sync_death() -> void:
	if is_dead:
		return
	health = 0.0
	_die()

# Audit ammo bug: clients never see server-side ammo mutation (V38 skips weapon
# sim client-side), so HUD ammo froze at max. Server broadcasts per-slot ammo on
# change; reliable because change-driven (a dropped final packet never self-corrects).
func _broadcast_ammo_changes() -> void:
	for i in _weapons.size():
		if not is_instance_valid(_weapons[i]):
			continue
		var a: int = _weapons[i].ammo
		if a != _ammo_synced[i]:
			_ammo_synced[i] = a
			_sync_ammo.rpc(i, a)

# B32: server forwards hit confirms to the owning peer (WeaponBase._emit_hit_if_visible);
# re-emitting the local weapon's signal reuses the existing HUD register_hit connections.
@rpc("authority", "unreliable_ordered")
func _sync_hit_confirmed(slot: int) -> void:
	Game.sync_log_event("hit_confirm", name, {"slot": slot})
	if slot >= 0 and slot < _weapons.size() and is_instance_valid(_weapons[slot]):
		_weapons[slot].hit_confirmed.emit()

@rpc("authority", "reliable")
func _sync_ammo(slot: int, a: int) -> void:
	if slot >= 0 and slot < _weapons.size() and is_instance_valid(_weapons[slot]):
		_weapons[slot].ammo = a

@rpc("authority", "unreliable_ordered")
func _sync_shield(pool: float) -> void:
	if _energy_shield != null:
		_energy_shield.set("shield_hp", pool)

# T119: called by Arena._rpc_snapshot on clients to push a server transform sample.
func receive_snapshot(entry: Dictionary) -> void:
	_snap_buf.append({
		"time": Time.get_ticks_msec() * 0.001,
		"pos": entry.get("pos", global_position),
		"quat": entry.get("quat", global_transform.basis.get_rotation_quaternion()),
		"vel": entry.get("vel", Vector3.ZERO),
		"torso_y": entry.get("torso_y", torso.rotation.y),
	})
	if _snap_buf.size() > 2:
		_snap_buf.pop_front()

func _do_shield_flash() -> void:
	if _flash_mat == null:
		return
	for mesh in _body_meshes:
		mesh.material_override = _flash_mat
	_flash_timer_es = _ES_FLASH_DUR

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	Game.ai_director_clear_intent(self)
	print("[Mech] %s destroyed" % name)
	SoundManager.play_sfx("mech_death", global_position)
	VFX.death_explosion(global_position + Vector3(0, 0.8, 0))
	set_physics_process(false)
	set_process(false)
	$CollisionShape3D.disabled = true
	if _input_source != null and _input_source.has_method("is_human_input") and _input_source.is_human_input():
		_launch_cockpit_pod()
	visible = false
	died.emit()

# Spawns a cockpit pod that rockets upward with a smoke trail and auto-destructs.
func _launch_cockpit_pod() -> void:
	var pod := RigidBody3D.new()
	pod.gravity_scale = 0.0
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.55, 0.35, 0.65)
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.55, 0.9)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.set_surface_override_material(0, mat)
	pod.add_child(mi)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.55, 0.35, 0.65)
	col.shape = shape
	pod.add_child(col)

	# Smoke trail emitted downward from pod base.
	var smoke := CPUParticles3D.new()
	smoke.emitting = true
	smoke.amount = 24
	smoke.lifetime = 1.2
	smoke.speed_scale = 1.0
	smoke.local_coords = false
	smoke.direction = Vector3(0, -1, 0)
	smoke.spread = 18.0
	smoke.initial_velocity_min = 1.0
	smoke.initial_velocity_max = 3.0
	smoke.gravity = Vector3.ZERO
	smoke.scale_amount_min = 0.3
	smoke.scale_amount_max = 0.7
	smoke.color = Color(0.85, 0.85, 0.85, 0.6)
	smoke.position = Vector3(0, -0.2, 0)
	pod.add_child(smoke)

	pod.position = global_position + Vector3(0, 1.8, 0)
	var spread_x: float = randf_range(-3.0, 3.0)  # cosmetic
	var spread_z: float = randf_range(-3.0, 3.0)  # cosmetic
	pod.linear_velocity = Vector3(spread_x, randf_range(22.0, 30.0), spread_z)  # cosmetic
	pod.angular_velocity = Vector3(randf_range(-2.0, 2.0), randf_range(-1.0, 1.0), randf_range(-2.0, 2.0))
	get_parent().add_child(pod)
	# Auto-destruct after 6 seconds.
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func(): if is_instance_valid(pod): pod.queue_free())

func make_camera_current() -> void:
	camera.make_current()

func set_input_source(source: Node) -> void:
	_input_source = source
	if source != null and source.has_method("is_human_input") and source.is_human_input():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func apply_modifier(stat: String, value: float) -> void:
	_modifiers[stat] = value

func remove_modifier(stat: String) -> void:
	_modifiers.erase(stat)

const _MAX_STEP  := 0.37   # slightly above step geometry (0.35m) for margin
const _STEP_RATE := 2.5    # m/s vertical lift speed while stepping up
var _step_up_remaining: float = 0.0

func _physics_process(delta: float) -> void:
	# V38: non-server peers skip all local simulation; transforms driven by snapshot interp.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_apply_snapshot_interp()
		if _input_source != null and owner_peer_id == multiplayer.get_unique_id():
			_handle_look()   # camera still tracks local mouse
			_maybe_forward_input()
		_update_legs(delta)
		return

	if not is_on_floor() and _step_up_remaining <= 0.0:
		velocity += get_gravity() * delta

	if _input_source != null:
		_handle_look()
		_handle_movement(delta)
		_handle_slot_toggle()
		_handle_reload()
		_handle_fire()
		_handle_ability()
		if _input_source.has_method("is_human_input") and _input_source.is_human_input():
			_update_lock(delta)
			if _input_source.is_mark_pressed():
				mark_requested.emit(global_position)

	if multiplayer.has_multiplayer_peer():
		_broadcast_ammo_changes()

	_try_step_up()
	if _step_up_remaining > 0.0:
		var lift := minf(_step_up_remaining, _STEP_RATE * delta)
		position.y += lift
		_step_up_remaining -= lift
	move_and_slide()
	_try_step_up_from_collisions()
	_update_legs(delta)

func _try_step_up() -> void:
	if not is_on_floor() and _step_up_remaining <= 0.0:
		return
	var horiz := Vector3(velocity.x, 0.0, velocity.z)

	var dirs: Array[Vector3] = []
	if _desired_move_dir != Vector3.ZERO:
		dirs.append(_desired_move_dir)
	if horiz.length_squared() >= 0.01:
		var vel_dir := horiz.normalized()
		if dirs.is_empty() or vel_dir.dot(dirs[0]) < 0.99:
			dirs.append(vel_dir)
	if dirs.is_empty():
		return

	var space := get_world_3d().direct_space_state
	var ex    := [get_rid()]
	var mask  := collision_mask
	for dir in dirs:
		if _check_step_dir(dir, space, ex, mask):
			return

func _try_step_up_from_collisions() -> void:
	if _step_up_remaining > 0.0:
		return
	var space := get_world_3d().direct_space_state
	var ex    := [get_rid()]
	var mask  := collision_mask
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var n   := col.get_normal()
		if abs(n.y) > 0.3:
			continue
		var step_dir := Vector3(-n.x, 0.0, -n.z).normalized()
		if _check_step_dir(step_dir, space, ex, mask):
			return

func _check_step_dir(dir: Vector3, space: PhysicsDirectSpaceState3D, ex: Array, mask: int) -> bool:
	var shin := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 0.1, 0),
		global_position + Vector3(0, 0.1, 0) + dir * 0.8, mask)
	shin.exclude = ex
	if not space.intersect_ray(shin):
		return false
	var clear := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, _MAX_STEP + 0.05, 0),
		global_position + Vector3(0, _MAX_STEP + 0.05, 0) + dir * 0.8, mask)
	clear.exclude = ex
	if space.intersect_ray(clear):
		return false
	_step_up_remaining = _MAX_STEP
	velocity.y = 0.0
	return true

func _update_legs(delta: float) -> void:
	legs.call("update_gait", velocity, global_transform.basis, leg_rotation_speed, walk_speed, delta)

func _apply_snapshot_interp() -> void:
	if _snap_buf.is_empty():
		return
	var now := Time.get_ticks_msec() * 0.001
	var render_t := now - 0.1
	var interp_torso_y: float = torso.rotation.y
	if _snap_buf.size() == 1:
		global_transform = Transform3D(Basis(_snap_buf[0]["quat"] as Quaternion), _snap_buf[0]["pos"] as Vector3)
		velocity = _snap_buf[0]["vel"] as Vector3
		interp_torso_y = _snap_buf[0].get("torso_y", torso.rotation.y)
	else:
		var s0: Dictionary = _snap_buf[0]
		var s1: Dictionary = _snap_buf[1]
		var span: float = (s1["time"] as float) - (s0["time"] as float)
		var t: float = 0.0
		if span > 0.0001:
			t = clampf((render_t - (s0["time"] as float)) / span, 0.0, 1.0)
		global_transform = Transform3D(
			Basis((s0["quat"] as Quaternion).slerp(s1["quat"] as Quaternion, t)),
			(s0["pos"] as Vector3).lerp(s1["pos"] as Vector3, t))
		velocity = (s0["vel"] as Vector3).lerp(s1["vel"] as Vector3, t)
		interp_torso_y = lerp_angle(
			s0.get("torso_y", torso.rotation.y) as float,
			s1.get("torso_y", torso.rotation.y) as float, t)
	if owner_peer_id != multiplayer.get_unique_id():
		torso.rotation.y = interp_torso_y

func _maybe_forward_input() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		return
	if owner_peer_id != multiplayer.get_unique_id():
		_net_look_accum = Vector2.ZERO  # discard accumulation for mechs we don't own
		return
	_net_input_tick += 1
	if _net_input_tick % 2 != 0:
		return
	var payload := {
		"move": _input_source.get_move_direction(),
		"look": _net_look_accum,
		"fire_prim": _input_source.is_firing_primary(),
		"fire_sec": _input_source.is_firing_secondary(),
		"slot_toggle": _input_source.get_slot_toggle(),
		"reload": _input_source.is_reload_pressed(),
		"ability": _input_source.is_ability_pressed(),
	}
	_net_look_accum = Vector2.ZERO
	_net_input_seq += 1
	rpc_id(1, &"_rpc_input", _net_input_seq, payload)

@rpc("any_peer", "unreliable_ordered")
func _rpc_input(seq: int, payload: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != owner_peer_id:
		push_error("[Mech] _rpc_input: sender %d doesn't own this mech (owner=%d)" % [sender, owner_peer_id])
		return
	var now := Time.get_ticks_msec() / 1000.0
	while not _rpc_rate_times.is_empty() and now - float(_rpc_rate_times[0]) > 1.0:
		_rpc_rate_times.pop_front()
	_rpc_rate_times.append(now)
	if _rpc_rate_times.size() > 60:
		if not _rpc_rate_warned:
			push_warning("[Mech] _rpc_input: rate limit exceeded for peer %d (>60Hz)" % sender)
			_rpc_rate_warned = true
		return
	_rpc_rate_warned = false
	if _input_source == null or not _input_source.has_method("push_input"):
		return
	_input_source.push_input(payload)

func _handle_look() -> void:
	var look: Vector2 = _input_source.get_look_delta()
	_net_look_accum += look
	if not multiplayer.has_multiplayer_peer() or multiplayer.is_server():
		_net_look_accum = Vector2.ZERO
	if look == Vector2.ZERO:
		return
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
	torso.rotate_y(-look.x * sens)
	_camera_pitch = clamp(_camera_pitch - look.y * sens, -1.2, 0.4)
	# camera_arm.rotation.x is owned by _process (shake + pitch combined)

func _handle_movement(delta: float) -> void:
	var dir2d: Vector2 = _input_source.get_move_direction()
	if not is_on_floor() and _step_up_remaining <= 0.0:
		if dir2d != Vector2.ZERO:
			var aim := torso.global_transform.basis
			_desired_move_dir = (aim.x * dir2d.x + (-aim.z) * -dir2d.y).normalized()
		return
	if dir2d == Vector2.ZERO:
		_desired_move_dir = Vector3.ZERO
		velocity.x = move_toward(velocity.x, 0.0, walk_speed * 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, walk_speed * 8.0 * delta)
		return
	var aim := torso.global_transform.basis
	var forward := -aim.z
	var right := aim.x
	_desired_move_dir = (right * dir2d.x + forward * -dir2d.y).normalized()
	velocity.x = move_toward(velocity.x, _desired_move_dir.x * walk_speed, turn_acceleration * delta)
	velocity.z = move_toward(velocity.z, _desired_move_dir.z * walk_speed, turn_acceleration * delta)

func _handle_slot_toggle() -> void:
	var idx: int = _input_source.get_slot_toggle()
	if idx >= 0:
		toggle_weapon_slot(idx)

func _handle_reload() -> void:
	if not _input_source.is_reload_pressed():
		return
	for weapon in _weapons:
		if is_instance_valid(weapon) and weapon.has_method("try_reload"):
			weapon.try_reload()

const _LOCK_CONE_COS := 0.99619  # cos(5 degrees) - acquisition angle
const _LOCK_RANGE    := 200.0

func _update_lock(delta: float) -> void:
	var cam_pos := camera.global_position
	var cam_fwd := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var ex := get_exclude_rids()

	var q := PhysicsRayQueryParameters3D.create(cam_pos, cam_pos + cam_fwd * _LOCK_RANGE)
	q.exclude = ex
	var result := space.intersect_ray(q)
	var candidate: Node3D = null
	if result:
		var col := result.collider as Node3D
		if col != null and col.is_in_group("mechs") and not col.get("is_stealthy") and not col.get("is_dead"):
			var col_team: int = int(col.get("team")) if "team" in col else -1
			if col_team != team:
				candidate = col

	# B22/B23 (complete fix): hold cone applies whether the raycast hit a different mech
	# or missed entirely. If current _lock_candidate is still within the hold cone, prefer
	# it over a raycast-found mech - prevents switching when two mechs are side by side.
	if _lock_candidate != null and candidate != _lock_candidate \
			and is_instance_valid(_lock_candidate) \
			and not _lock_candidate.get("is_dead") and not _lock_candidate.get("is_stealthy"):
		var to_cur := (_lock_candidate as Node3D).global_position - cam_pos
		var cur_dist := to_cur.length()
		if cur_dist > 0.001:
			var hold_cos := cos(deg_to_rad(7.0) * clampf(_LOCK_RANGE / cur_dist, 1.0, 6.0))
			if cam_fwd.dot(to_cur / cur_dist) >= hold_cos:
				candidate = _lock_candidate

	if candidate == null:
		var best_cos := _LOCK_CONE_COS
		for mech: Node in get_tree().get_nodes_in_group("mechs"):
			if mech == self:
				continue
			if mech.get("is_stealthy") or mech.get("is_dead"):
				continue
			var mech_team: int = int(mech.get("team")) if "team" in mech else -1
			if mech_team == team:
				continue
			var mech3d := mech as Node3D
			var to_mech := mech3d.global_position - cam_pos
			var dist := to_mech.length()
			if dist > _LOCK_RANGE or dist < 0.001:
				continue
			var dot := cam_fwd.dot(to_mech / dist)
			if dot < best_cos:
				continue
			best_cos = dot
			candidate = mech3d

	lock_eligible = candidate != null
	lock_eligible_target = candidate
	if not has_lock_weapon():
		_set_locked_target(null)
		lock_progress = 0.0
		_lock_timer = 0.0
		# _lock_candidate intentionally kept - hold cone needs it for indicator stability
		return
	if candidate == null:
		_lock_timer = 0.0
		_lock_candidate = null
		_set_locked_target(null)
		lock_progress = 0.0
	elif candidate != _lock_candidate:
		_lock_candidate = candidate
		_lock_timer = 0.0
		_set_locked_target(null)
		lock_progress = 0.0
	else:
		_lock_timer = minf(_lock_timer + delta, _lock_time)
		lock_progress = _lock_timer / _lock_time
		if _lock_timer >= _lock_time:
			_set_locked_target(_lock_candidate if is_instance_valid(_lock_candidate) else null)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_broadcast_lock_state()

func _set_locked_target(node: Node3D) -> void:
	locked_target = node

# T102/B33: lock runs server-side only (V38), so client HUD lock ring + red box
# were dead and the lock_target oracle had no client state to compare. Discrete
# transitions (target/eligible changed) go reliable per V44; the progress ramp
# rides unreliable_ordered (self-corrects next tick, ends in a reliable transition).
var _lock_synced_name: String = ""
var _elig_synced_name: String = ""
var _lock_synced_progress: float = 0.0

func _broadcast_lock_state() -> void:
	var ln: String = String(locked_target.name) if is_instance_valid(locked_target) else ""
	var en: String = String(lock_eligible_target.name) if is_instance_valid(lock_eligible_target) else ""
	if ln != _lock_synced_name or en != _elig_synced_name:
		_lock_synced_name = ln
		_elig_synced_name = en
		_lock_synced_progress = lock_progress
		_sync_lock_state.rpc(ln, en, lock_progress)
	elif lock_progress != _lock_synced_progress:
		_lock_synced_progress = lock_progress
		_sync_lock_progress.rpc(lock_progress)

# V31: cross-peer mech refs travel as names (unique, mirrors sync-log mech_id).
func _find_mech(mech_name: String) -> Node3D:
	if mech_name == "":
		return null
	for m in get_tree().get_nodes_in_group("mechs"):
		if String(m.name) == mech_name:
			return m
	return null

@rpc("authority", "reliable")
func _sync_lock_state(ln: String, en: String, p: float) -> void:
	locked_target = _find_mech(ln)
	lock_eligible_target = _find_mech(en)
	lock_eligible = lock_eligible_target != null
	lock_progress = p

@rpc("authority", "unreliable_ordered")
func _sync_lock_progress(p: float) -> void:
	lock_progress = p

func _handle_fire() -> void:
	var primary: bool   = _input_source.is_firing_primary()
	var secondary: bool = _input_source.is_firing_secondary()
	if _was_firing_primary and not primary:
		for i in _weapons.size():
			if is_instance_valid(_weapons[i]):
				_weapons[i].on_fire_release()
	_was_firing_primary = primary
	if not primary and not secondary:
		return
	for i in _weapons.size():
		if not is_instance_valid(_weapons[i]):
			continue
		if primary or (secondary and _active_set[i]):
			fire_weapon(i)

func _handle_ability() -> void:
	var delta: float = get_physics_process_delta_time()
	for key in _ability_cooldowns.keys():
		if _ability_cooldowns[key] > 0.0:
			_ability_cooldowns[key] = maxf(0.0, _ability_cooldowns[key] - delta)
	for key in _ability_active_timers.keys():
		if _ability_active_timers[key] > 0.0:
			_ability_active_timers[key] = maxf(0.0, _ability_active_timers[key] - delta)
			if _ability_active_timers[key] == 0.0:
				_deactivate_ability(key)
	if not _input_source.is_ability_pressed():
		return
	for ability in _abilities:
		if ability.trigger != 0:
			continue
		var key: String = ability.effect_key
		if _ability_cooldowns.get(key, 0.0) > 0.0:
			return
		if _ability_active_timers.get(key, 0.0) > 0.0:
			return
		_activate_ability(ability)

func _apply_stealth_visual(active: bool) -> void:
	var all_meshes := find_children("*", "MeshInstance3D", true, false)
	if active:
		_stealth_saved_mats.clear()
		var shader := load("res://shaders/stealth_camo.gdshader") as Shader
		var mat: Material
		if shader != null:
			var sm := ShaderMaterial.new()
			sm.shader = shader
			sm.render_priority = 1
			mat = sm
		else:
			var fb := StandardMaterial3D.new()
			fb.albedo_color = Color(0.07, 0.10, 0.07)
			fb.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat = fb
		for mesh in all_meshes:
			if mesh is MeshInstance3D:
				_stealth_saved_mats[mesh] = mesh.get_surface_override_material(0)
				mesh.set_surface_override_material(0, mat)
	else:
		for mesh in all_meshes:
			if mesh is MeshInstance3D and _stealth_saved_mats.has(mesh):
				mesh.set_surface_override_material(0, _stealth_saved_mats[mesh])
		_stealth_saved_mats.clear()

func _activate_ability(ability: Resource) -> void:
	match ability.effect_key:
		"jump_heal":
			velocity.y = 15.0
			var launch_dir: Vector3 = _desired_move_dir if _desired_move_dir != Vector3.ZERO \
				else -torso.global_transform.basis.z
			velocity.x = launch_dir.x * walk_speed * 3.75
			velocity.z = launch_dir.z * walk_speed * 3.75
			health = minf(health + 80.0, max_health)
		"stealth":
			is_stealthy = true
			_apply_stealth_visual(true)
	if ability.duration > 0.0:
		_ability_active_timers[ability.effect_key] = ability.duration
	else:
		var cd: float = ability.cooldown
		if _input_source.has_method("is_human_input") and _input_source.is_human_input():
			cd *= maxf(0.0, 1.0 - Game.get_skill_effect("ability_recharge"))
		_ability_cooldowns[ability.effect_key] = cd
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var slot := _abilities.find(ability)
		if slot >= 0:
			_rpc_ability_activated.rpc(slot)

func _deactivate_ability(key: String) -> void:
	match key:
		"stealth":
			is_stealthy = false
			_apply_stealth_visual(false)
	for ability in _abilities:
		if ability.effect_key == key:
			var cd: float = ability.cooldown
			if _input_source != null and _input_source.has_method("is_human_input") and _input_source.is_human_input():
				cd *= maxf(0.0, 1.0 - Game.get_skill_effect("ability_recharge"))
			_ability_cooldowns[key] = cd
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				_rpc_ability_deactivated.rpc(_abilities.find(ability))
			break

@rpc("authority", "unreliable_ordered")
func _rpc_ability_activated(slot: int) -> void:
	if slot < 0 or slot >= _abilities.size():
		return
	var ability: Resource = _abilities[slot]
	match ability.effect_key:
		"stealth":
			is_stealthy = true
			_apply_stealth_visual(true)

@rpc("authority", "unreliable_ordered")
func _rpc_ability_deactivated(slot: int) -> void:
	if slot < 0 or slot >= _abilities.size():
		return
	var ability: Resource = _abilities[slot]
	match ability.effect_key:
		"stealth":
			is_stealthy = false
			_apply_stealth_visual(false)
