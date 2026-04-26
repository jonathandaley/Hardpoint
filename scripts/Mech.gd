class_name Mech
extends CharacterBody3D
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

@export var base_walk_speed: float = 3.15
@export var base_reload_rate: float = 1.0
@export var max_health: float = 500.0
@export var team: int = 0
@export var turn_acceleration: float = 60.0   # m/s² per axis - velocity direction change rate
@export var leg_rotation_speed: float = 15.0  # rad/s - leg visual tracking speed

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

@onready var torso: Node3D = $Torso
@onready var legs: Node3D = $Legs
@onready var camera: Camera3D = $Torso/CameraArm/Camera3D
@onready var camera_arm: SpringArm3D = $Torso/CameraArm
@onready var _shield := $Torso/PhysicalShield
@onready var _energy_shield: Node = $EnergyShield

var _body_meshes: Array = []
var _flash_mat: StandardMaterial3D = null
var _flash_timer_es: float = 0.0
const _ES_FLASH_DUR := 0.12
var _stealth_saved_mats: Dictionary = {}  # MeshInstance3D -> original material

var _weapons: Array = []
var _active_set: Array = []  # parallel bool array; true = included in right-click subset
var _was_firing_primary: bool = false

var locked_target: Node3D = null
var lock_progress: float = 0.0
var lock_eligible: bool = false
var lock_eligible_target: Node3D = null
var _lock_candidate: Node3D = null
var _lock_timer: float = 0.0
const _LOCK_TIME := 3.0

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
	for child in torso.get_children():
		if child is MeshInstance3D:
			_body_meshes.append(child)

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
				mesh.material_overlay = null

func apply_camera_shake(magnitude: float) -> void:
	_shake_intensity = magnitude
	_shake_timer = _SHAKE_DURATION

func configure_energy_shield(has_shield: bool, max_hp: float, regen_rate: float, regen_delay: float) -> void:
	if not has_shield:
		return
	_energy_shield.call("activate", max_hp, regen_rate, regen_delay)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.albedo_color = Color(0.3, 0.8, 1.0, 0.55)
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

func configure_shield(has_shield: bool, max_hp: float = 300.0) -> void:
	if has_shield:
		_shield.activate(max_hp)
	# disabled by default in scene; no action needed for mechs without shields

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

func take_damage(amount: float) -> void:
	if health <= 0.0 or invincible:
		return
	var actual := amount
	if _energy_shield != null:
		var overflow: float = _energy_shield.call("absorb", amount)
		if overflow < amount:
			_do_shield_flash()
		actual = overflow
	if actual <= 0.0:
		return
	health -= actual
	damage_taken_total += actual
	damaged.emit()
	SoundManager.play_sfx("damage_hit", global_position)
	print("[Mech] %s  %.0f / %.0f HP" % [name, health, max_health])
	if health <= 0.0:
		health = 0.0
		_die()

func _do_shield_flash() -> void:
	if _flash_mat == null:
		return
	for mesh in _body_meshes:
		mesh.material_overlay = _flash_mat
	_flash_timer_es = _ES_FLASH_DUR

func _die() -> void:
	print("[Mech] %s destroyed" % name)
	SoundManager.play_sfx("mech_death", global_position)
	VFX.death_explosion(global_position + Vector3(0, 0.8, 0))
	set_physics_process(false)
	set_process(false)
	$CollisionShape3D.disabled = true
	visible = false
	died.emit()

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
	legs.call("update_gait", velocity, global_transform.basis, leg_rotation_speed, delta)

func _handle_look() -> void:
	var look: Vector2 = _input_source.get_look_delta()
	if look == Vector2.ZERO:
		return
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
	torso.rotate_y(-look.x * sens)
	_camera_pitch = clamp(_camera_pitch - look.y * sens, -1.2, 0.4)
	# camera_arm.rotation.x is owned by _process (shake + pitch combined)

func _handle_movement(delta: float) -> void:
	var dir2d: Vector2 = _input_source.get_move_direction()
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

const _LOCK_CONE_COS := 0.99619  # cos(5 degrees)

func _update_lock(delta: float) -> void:
	var cam_pos := camera.global_position
	var cam_fwd := -camera.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var ex := get_exclude_rids()

	var q := PhysicsRayQueryParameters3D.create(cam_pos, cam_pos + cam_fwd * 200.0)
	q.exclude = ex
	var result := space.intersect_ray(q)
	var candidate: Node3D = null
	if result:
		var col := result.collider as Node3D
		if col != null and col.is_in_group("mechs") and not col.get("is_stealthy"):
			var col_team: int = int(col.get("team")) if "team" in col else -1
			if col_team != team:
				candidate = col

	if candidate == null:
		var best_cos := _LOCK_CONE_COS
		for mech: Node in get_tree().get_nodes_in_group("mechs"):
			if mech == self:
				continue
			if mech.get("is_stealthy"):
				continue
			var mech_team: int = int(mech.get("team")) if "team" in mech else -1
			if mech_team == team:
				continue
			var mech3d := mech as Node3D
			var to_mech := mech3d.global_position - cam_pos
			var dist := to_mech.length()
			if dist > 200.0 or dist < 0.001:
				continue
			var dot := cam_fwd.dot(to_mech / dist)
			if dot < best_cos:
				continue
			best_cos = dot
			candidate = mech3d

	lock_eligible = candidate != null
	lock_eligible_target = candidate
	if not has_lock_weapon():
		locked_target = null
		lock_progress = 0.0
		_lock_timer = 0.0
		_lock_candidate = null
		return
	if candidate == null:
		_lock_timer = 0.0
		_lock_candidate = null
		locked_target = null
		lock_progress = 0.0
	elif candidate != _lock_candidate:
		_lock_candidate = candidate
		_lock_timer = 0.0
		locked_target = null
		lock_progress = 0.0
	else:
		_lock_timer = minf(_lock_timer + delta, _LOCK_TIME)
		lock_progress = _lock_timer / _LOCK_TIME
		if _lock_timer >= _LOCK_TIME:
			locked_target = _lock_candidate

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
			_weapons[i].fire()

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
			velocity.y = 15.6
			health = minf(health + 80.0, max_health)
			damaged.emit()
		"stealth":
			is_stealthy = true
			_apply_stealth_visual(true)
	if ability.duration > 0.0:
		_ability_active_timers[ability.effect_key] = ability.duration
	else:
		_ability_cooldowns[ability.effect_key] = ability.cooldown

func _deactivate_ability(key: String) -> void:
	match key:
		"stealth":
			is_stealthy = false
			_apply_stealth_visual(false)
	for ability in _abilities:
		if ability.effect_key == key:
			_ability_cooldowns[key] = ability.cooldown
			break
