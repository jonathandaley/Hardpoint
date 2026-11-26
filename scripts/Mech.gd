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
signal damage_event(amount: float, source: Node)  # T243: who hit whom, for the balance tester

@export var base_walk_speed: float = 3.15
@export var max_health: float = 500.0
@export var team: int = 0
@export var turn_acceleration: float = 60.0   # m/s² per axis - velocity direction change rate
@export var leg_rotation_speed: float = 15.0  # rad/s - leg visual tracking speed

var owner_peer_id: int = 0
var health: float = 0.0
var damage_taken_total: float = 0.0
var damage_dealt_total: float = 0.0  # T168: to enemies, credited on the authoritative peer
var roster_idx: int = -1  # T168: MP roster entry this mech belongs to (squad respawns share it)
var last_attacker: Node = null  # T169: enemy mech that last hurt us (bots retaliate); server-side
var is_stealthy: bool = false
var invincible: bool = false
var _modifiers: Dictionary = {}
var _input_source: Node = null   # InputSource - untyped to avoid cache dependency
var _abilities: Array = []
var _ability_cooldowns: Dictionary = {}  # key -> s until it can fire (with charges: until the next one)
var _ability_charges: Dictionary = {}  # T454: key -> [ready, s until the next is back, max, recharge s] (charges > 1)
var _ability_active_timers: Dictionary = {}
var _camera_pitch: float = -0.3  # matches CameraArm initial rotation.x
var _desired_move_dir: Vector3 = Vector3.ZERO
var _no_damage_timer: float = 0.0  # seconds since last damage hit; drives repair_rate skill
var _net_input_tick: int = 0       # increments every physics tick; used for 30Hz throttle
var _net_input_seq: int = 0        # monotonic send counter
var _press_counts: Array = [0, 0, 0, 0, 0, 0]  # T158/V47: cumulative presses [reload, ability, slot0..3]
var healed_others_total := 0.0  # T536: server, HP this mech's field repair restored to teammates
var last_input_ms: int = 0           # T167: server, wall ms of the owner's last _rpc_input (Arena silence check)
var input_ack: int = 0               # T205: server, newest input seq applied (rides the snapshot)
var input_ack_ticks: int = 0         # T205: server, physics ticks run on that input so far
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
const _WeaponVisuals := preload("res://scripts/WeaponVisuals.gd")
var _body_meshes: Array = []
var _flash_mat: StandardMaterial3D = null
var _flash_timer_es: float = 0.0
const _ES_FLASH_DUR := 0.12
var _stealth_saved_mats: Dictionary = {}  # MeshInstance3D -> original material

var _weapons: Array = []
var _ammo_synced: Array = []   # last ammo value broadcast per slot (server, MP only)
var _active_set: Array = []  # parallel bool array; true = included in right-click subset
## T532: how far this pilot's mortar lobs (m; < 0 = Mortar.LOB_DEFAULT), stepped by the wheel / arrows.
## The owner sets it; it rides the input payload to the server (V41: clamped where it's used).
var lob_range := -1.0
## T531: the local camera's scope zoom (1 = none), up to 1 + skill("scope_zoom") with a scoped weapon mounted.
## Camera only: aim stays the ray through the screen centre; mouse sensitivity scales down with it.
var scope_zoom := 1.0
var _base_fov := 0.0
const SCOPE_RANGE_M := 150.0
const SCOPE_STEP := 1.15  # T545: zoom x this a wheel notch (calibration knob)  # T531: weapons reaching past this scope (snipers, Patience), plus lasers; T535: not lock-on ones
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
var _shake_len := _SHAKE_DURATION  # T478: this shake's length (a stomp shakes longer)

var walk_speed: float:
	get: return base_walk_speed * _modifiers.get("walk_speed", 1.0) * terrain_speed * (STOMP_SLOW_K if slow_s > 0.0 else 1.0)
var terrain_speed := 1.0  # T225: set by the map each tick (swamp water slows wading mechs)

# ---- T462: respawned mechs and unreliable RPCs ----
# Net sweep 2026-11-17 (bot_lock@bad, 3 in ~8 runs): "Node not found: Arena/Mech_r2_s1/Torso/
# Hardpoint2/RifleLight", "Arena/Mech_r3_s1". ENet carries reliable and unreliable RPCs on separate
# channels, so under loss a respawned bot's gunfire / lock progress overtook its reliable spawn
# RPC and hit a node the client hadn't built yet. A mid-match respawn holds its unreliable RPCs
# (all cosmetic or HUD) for FX_HOLD_TICKS while the spawn lands.
# ponytail: a spawn RPC still in flight after 2 s would still miss; the exact fix is a per-client
# "built it" ack, which adds an RPC = a NET_VERSION bump -- do it with the next release's bump.
const FX_HOLD_TICKS := 120  # 2 s at 60 Hz: past a reliable resend or two on a bad link
var _fx_hold_until := 0

func hold_fx_after_respawn() -> void:
	_fx_hold_until = Engine.get_physics_frames() + FX_HOLD_TICKS

## An unreliable RPC of `node` (this mech or one of its weapons), unless this mech just respawned.
func rpc_fx(node: Node, method: StringName, args: Array) -> void:
	if Engine.get_physics_frames() < _fx_hold_until:
		return
	node.callv("rpc", [method] + args)

func _ready() -> void:
	add_to_group("mechs")
	# T235: the camera arm casts a ball, not a ray: a ray parks the camera 1 cm off a wall or
	# ceiling and the near plane cuts through it (the roofed Corvette's corridors)
	var ball := SphereShape3D.new()
	ball.radius = CAMERA_CLEAR
	camera_arm.shape = ball
	camera_arm.add_excluded_object(get_rid())
	health = max_health
	_setup_weapon_owners()
	_build_weapon_list()
	_body_meshes = torso.find_children("*", "MeshInstance3D", true, false)

# T196 (user 2026-11-02: over-the-shoulder): the camera arm sits beside the torso so the
# mech is left of the crosshair instead of blocking it; V swaps sides (Game.shoulder).
# Aim stays camera-based (rays from the camera), so the crosshair stays true. A sideways
# probe pulls the arm in against a wall: a SpringArm whose origin is inside a wall can't
# see it and puts the camera in it. Every human-owned mech runs this on every peer --
# server-side weapons (laser, hitscan) aim from the server's copy of the camera, so the
# server must offset it exactly like the owner's screen (B83): the side rides the input.
const SHOULDER_X := 1.3
const CAMERA_CLEAR := 0.25  # T235: camera arm ball radius (local units)
var shoulder := 0.0  # this mech's side: the owner's Game.shoulder, sent with its input (T252: 0 = center)
var _shoulder_x := 0.0

# T237 (user 2026-11-04: "Vesuvius crosshair is obstructed by his giant shoulder"): the
# camera sits beside the widest part of this mech (body + guns, torso-local) instead of a
# fixed SHOULDER_X, so the crosshair ray -- straight ahead from the camera, only pitched --
# passes beside it at any pitch (Everest / Vesuvius reach 1.52 > 1.3). Measured once from
# the kit meshes, which every peer builds the same (B83: the server aims from its copy).
var _shoulder_reach := -1.0

func _side_offset() -> float:
	if _shoulder_reach < 0.0:
		_shoulder_reach = 0.0
		var inv := torso.global_transform.affine_inverse()
		for mi in torso.find_children("*", "MeshInstance3D", true, false):
			var n := mi as MeshInstance3D
			if n.mesh == null or not n.is_visible_in_tree():
				continue
			var box: AABB = inv * n.global_transform * n.get_aabb()
			_shoulder_reach = maxf(_shoulder_reach, maxf(absf(box.position.x), absf(box.end.x)))
	return maxf(SHOULDER_X, _shoulder_reach + 0.3)

# T252 (HUMAN_FOUND_ISSUES 2026-11-05: over-the-shoulder aiming "doesn't really work";
# user: raised center view): shoulder 0 = camera straight behind with the arm pivot raised
# above the mech's highest part (body + guns). A SpringArm camera looks through its pivot,
# so the crosshair ray then passes over the mech instead of through it.
# Past the pivot the ray keeps descending (pitch), so the clearance also covers the mech's
# fore / aft reach at CENTER_PITCH (a long top gun -- Slip, Seeker -- lifts the camera more).
const CENTER_CLEAR := 0.45  # minimum pivot height over the mech's top, torso-local
const CENTER_PITCH := 0.6   # clear down to this pitch (rad)
var _arm_y := -1.0           # the scene's arm height (shoulder view)
var _center_y := -1.0

# T319 (HUMAN_FOUND 2026-11-05: "Targeting reticule should aim for center mass, instead of the
# current spot (appears constant, so it's a little low on a pegasus and very low on a
# vesuvius)"): the middle of the mech's visible body, kept in its own space (scale and yaw
# carried by to_global); the soft-lock box, homing rockets, the arc, bot aim and lock-on all
# aim here instead of each using its own fixed height.
var _cm_local := Vector3.INF

func center_mass() -> Vector3:
	if _cm_local == Vector3.INF:
		var inv := global_transform.affine_inverse()
		var box := AABB()
		var first := true
		for mi in find_children("*", "MeshInstance3D", true, false):
			var n := mi as MeshInstance3D
			if n.mesh == null or not n.visible or n.get_script() != null:  # the blob shadow has a script
				continue
			var b: AABB = inv * n.global_transform * n.get_aabb()
			box = b if first else box.merge(b)
			first = false
		_cm_local = box.get_center() if not first else Vector3.UP
		# B125 (T339): keep it inside the hit capsule -- a big forward-hung gun (Seeker's heavy MG)
		# pulled the mesh centre 0.84 m out in front, where rays aimed at it (arc, bots) met nothing
		var cs := get_node_or_null("CollisionShape3D") as CollisionShape3D
		if cs != null and cs.shape is CapsuleShape3D:
			var cap := cs.shape as CapsuleShape3D
			var axis := Vector2(cs.position.x, cs.position.z)
			var h := axis + (Vector2(_cm_local.x, _cm_local.z) - axis).limit_length(cap.radius * 0.6)
			var half := cap.height * 0.5 - cap.radius * 0.4
			_cm_local = Vector3(h.x, clampf(_cm_local.y, cs.position.y - half, cs.position.y + half), h.y)
	return to_global(_cm_local)

func _center_pivot_y() -> float:
	if _center_y < 0.0:
		var top := 0.0
		var reach := 0.0
		var inv := torso.global_transform.affine_inverse()
		for mi in torso.find_children("*", "MeshInstance3D", true, false):
			var n := mi as MeshInstance3D
			if n.mesh == null or not n.is_visible_in_tree():
				continue
			var box: AABB = inv * n.global_transform * n.get_aabb()
			top = maxf(top, box.end.y)
			reach = maxf(reach, maxf(absf(box.position.z), absf(box.end.z)))
		_center_y = top + maxf(CENTER_CLEAR, reach * tan(CENTER_PITCH) + 0.1)
	return _center_y

func _update_shoulder(delta: float) -> void:
	if _arm_y < 0.0:
		_arm_y = camera_arm.position.y
	if owner_peer_id == multiplayer.get_unique_id():  # our own mech: V swaps (shoulder view)
		if camera.current and Input.is_action_just_pressed("swap_shoulder") and Game.shoulder != 0.0:
			Game.shoulder = -Game.shoulder
		shoulder = Game.shoulder
	var want_y := maxf(_arm_y, _center_pivot_y()) if shoulder == 0.0 else _arm_y
	# Never let the pivot come within the camera ball of a ceiling: the arm's cast then
	# starts touching it, reports no hit and the camera goes through the roof (Corvette,
	# jumping or a tall mech). Capped at once, not eased: a jump rises faster than the ease.
	var low := torso.global_transform * Vector3(0.0, _arm_y * 0.5, 0.0)
	var high := torso.global_transform * Vector3(0.0, want_y + CAMERA_CLEAR + 0.05, 0.0)
	var up := PhysicsRayQueryParameters3D.create(low, high, 1)
	up.exclude = [get_rid()]
	var roof := get_world_3d().direct_space_state.intersect_ray(up)
	var capped := false
	if not roof.is_empty():
		var lid: float = (torso.global_transform.affine_inverse() * (roof.position as Vector3)).y - CAMERA_CLEAR - 0.05
		if lid < want_y:
			want_y = lid
			capped = true
	camera_arm.position.y = minf(camera_arm.position.y, want_y) if capped and camera_arm.position.y > want_y \
		else move_toward(camera_arm.position.y, want_y, delta * 6.0)
	var want := _side_offset() * shoulder
	var y := camera_arm.position.y
	var from := torso.global_transform * Vector3(0.0, y, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, torso.global_transform * Vector3(want, y, 0.0), 1)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var room := maxf(0.0, from.distance_to(hit.position) / maxf(scale.x, 0.01) - 0.3)
		want = signf(want) * minf(absf(want), room)
	_shoulder_x = move_toward(_shoulder_x, want, delta * 6.0)  # eased swap, ~0.4 s
	camera_arm.position.x = _shoulder_x

func _process(delta: float) -> void:
	if _has_field_repair:
		_update_field_ring()  # T487
	if owner_peer_id != 0:  # bots keep a centred camera
		_update_shoulder(delta)
	_tilt_guns()
	if _shake_timer > 0.0:
		_shake_timer = maxf(0.0, _shake_timer - delta)
		var frac := _shake_timer / _shake_len
		camera_arm.rotation.x = _camera_pitch + randf_range(-_shake_intensity, _shake_intensity) * frac
	else:
		camera_arm.rotation.x = _camera_pitch
	if _flash_timer_es > 0.0:
		_flash_timer_es = maxf(0.0, _flash_timer_es - delta)
		if _flash_timer_es == 0.0:
			for mesh in _body_meshes:
				mesh.material_override = null
	var repair_eff: float = skill("repair_rate")  # T332: any pilot with the skill, bots too
	if repair_eff > 0.0 and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		_no_damage_timer += delta
		if _no_damage_timer >= 3.0 and health > 0.0 and health < max_health:
			health = minf(health + repair_eff * delta, max_health)  # clients: the snapshots carry it (T474)

# T329 (user 2026-11-05: "make the weapons tilt up and down as they aim"): every hardpoint pitches
# with the aim, clamped to TILT_MAX. Remote mechs get the pitch in the snapshot (their camera
# follows it). Muzzles and shot spawns follow.
# T353 (HUMAN_FOUND 2026-11-08: guns "aimed high, bots and players ... Make sure level camera means
# level gun. Actual bullets fire correctly, it's just the visual"): T329 tilted by a fixed offset
# from the raised view's usual pitch, so a level camera put every gun 0.3 rad high. Each hardpoint
# now points at what the crosshair is on (the camera ray's hit, or TILT_RAY_M out) -- the point
# ProjectileGun fires at.
const TILT_MAX := 0.45
const TILT_RAY_M := 200.0

func _tilt_guns() -> void:
	# T369 (HUMAN_FOUND 2026-11-09: hangar mechs' guns "30 degrees down, should be level"): a display
	# prop (out of "mechs", T176) has no aim; its own camera looks down at it, so guns stay level
	if camera == null or not is_inside_tree() or not is_in_group("mechs"):
		return
	var from := camera.global_position
	var fwd := -camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(from, from + fwd * TILT_RAY_M)
	q.exclude = get_exclude_rids()
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var aim: Vector3 = hit.position if not hit.is_empty() else from + fwd * TILT_RAY_M
	var inv := torso.global_transform.basis.orthonormalized().inverse()
	for hp in torso.get_children():
		if hp is Node3D and String(hp.name).begins_with("Hardpoint"):
			var d: Vector3 = inv * (aim - (hp as Node3D).global_position)
			(hp as Node3D).rotation.x = clampf(atan2(d.y, maxf(-d.z, 0.5)), -TILT_MAX, TILT_MAX)

## T478: Settings > CAMERA SHAKE turns every shake off (recoil and stomp); a weak shake never cuts
## a stronger one short.
func apply_camera_shake(magnitude: float, secs := _SHAKE_DURATION) -> void:
	if not bool(Game.settings.get("camera_shake", true)):
		return
	if _shake_timer > 0.0 and _shake_intensity * _shake_timer / _shake_len > magnitude:
		return
	_shake_intensity = magnitude
	_shake_timer = secs
	_shake_len = secs

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
		_adopt_shield_meshes()
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_shield.shield_broken.connect(func() -> void: _rpc_shield_broken.rpc())
	# disabled by default in scene; no action needed for mechs without shields

# T242 (user 2026-11-04: "Everest shield should disappear on breaking"): the kit model's
# shield (slab, face, cross, brackets -- the torso boxes inside the physical shield's
# volume) moves under the PhysicalShield node, which hides when it breaks.
const _SHIELD_GRAB := Vector3(0.1, 0.1, 0.3)  # slack around the shield box when adopting kit parts

## T427: also asked by MechVisuals._merge_parts (before _ready), which leaves these boxes
## unmerged so they can still move under the shield. shield = Torso/PhysicalShield, p in torso space.
static func in_shield_volume(shield: Node3D, p: Vector3) -> bool:
	var cs := shield.get_node_or_null("CollisionShape3D") as CollisionShape3D if shield != null else null
	if cs == null or not (cs.shape is BoxShape3D):
		return false
	var half: Vector3 = (cs.shape as BoxShape3D).size * 0.5 + _SHIELD_GRAB
	var q: Vector3 = (shield.transform * cs.transform).affine_inverse() * p
	return absf(q.x) <= half.x and absf(q.y) <= half.y and absf(q.z) <= half.z

func _adopt_shield_meshes() -> void:
	for c in torso.get_children():
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if in_shield_volume(_shield, mi.position):
			var local: Transform3D = _shield.transform.affine_inverse() * mi.transform
			torso.remove_child(mi)
			_shield.add_child(mi)
			mi.transform = local

# Server -> clients: the physical shield broke (damage is server-only, V38).
@rpc("authority", "reliable")
func _rpc_shield_broken() -> void:
	if is_instance_valid(_shield) and _shield.visible:
		_shield.call("_break")

# T332: this mech's pilot's skills (its roster entry, Arena._apply_skills) -- on a server the
# local profile (Game.get_skill_effect) is the host's own, not the pilot's.
var pilot_skills: Dictionary = {}

func skill(key: String) -> float:
	return Game.skill_effect_in(pilot_skills, key)

func apply_pilot_skills() -> void:
	max_health      *= 1.0 + skill("health")
	health           = max_health
	base_walk_speed *= 1.0 + skill("move_speed")
	_lock_time      *= maxf(0.1, 1.0 - skill("lock_speed"))
	var dmg_eff:    float = skill("damage")
	var spd_eff:    float = skill("projectile_speed")
	var rl_eff:     float = skill("reload_speed")
	var spread_eff: float = skill("spread_reduction")
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
		_energy_shield.max_shield_hp *= 1.0 + skill("shield_capacity")
		_energy_shield.shield_hp      = _energy_shield.max_shield_hp

func has_lock_weapon() -> bool:
	for w in _weapons:
		if is_instance_valid(w) and w.get("requires_lock") == true:
			return true
	return false

# T334: the farthest reach of our lock weapons (0 = none).
## T408: the farthest any equipped weapon reaches (0 = unarmed).
func weapon_range() -> float:
	var r := 0.0
	for w in _weapons:
		if is_instance_valid(w):
			r = maxf(r, float(w.get("range")))
	return r

func lock_weapon_range() -> float:
	var r := 0.0
	for w in _weapons:
		if is_instance_valid(w) and w.get("requires_lock") == true:
			r = maxf(r, float(w.get("range")))
	return r

func get_exclude_rids() -> Array:
	var rids: Array = [get_rid()]
	if is_instance_valid(_shield) and _shield.visible:
		rids.append(_shield.get_rid())
	return rids

var weapon_scale := 1.0  # T191: MechDef.weapon_scale, set before configure_weapons

func configure_weapons(slots: Array) -> void:
	if slots.is_empty():
		return
	_cm_local = Vector3.INF  # T319: recomputed with the new guns
	for child in torso.get_children():
		if child.name.begins_with("Hardpoint"):
			# B102: detach first -- a queued-but-attached "Hardpoint0" made the new one get
			# renamed, and the weapon list picked up the dying weapon (every second re-arm)
			torso.remove_child(child)
			child.queue_free()
	for i in slots.size():
		var slot = slots[i]
		var scene: PackedScene = slot.weapon_scene
		if scene == null:
			continue
		var weapon: Node = scene.instantiate()
		_WeaponVisuals.apply(weapon, weapon_scale)  # T180: kit model replaces the placeholder meshes
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
	_ability_charges.clear()
	_ability_active_timers.clear()
	is_stealthy = false
	_dash = false
	_charge = false
	_has_field_repair = false
	for ability in abilities:
		var key: String = ability.effect_key
		_dash = _dash or key == "dash"  # T454
		_has_field_repair = _has_field_repair or key == "field_repair"  # T487
		_charge = _charge or key == "charge"  # T473
		if ability.trigger == 1:
			_apply_passive(key)
		else:
			_ability_cooldowns[key] = 0.0
			if ability.charges > 1:
				_ability_charges[key] = [ability.charges, 0.0, ability.charges, 0.0]
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
		# B34/V44: toggles run server-side only (V38), so the client's WeaponHUD
		# icon dim (reads get_active_set) never updated. Full array: idempotent.
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_sync_active_set.rpc(_active_set)

@rpc("authority", "reliable")
func _sync_active_set(aset: Array) -> void:
	_active_set = aset.duplicate()

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
var last_fired_frame := -100000  # T407: bots hear a stealthed mech that's shooting

func fire_weapon(slot: int, aim: Vector3 = Vector3.ZERO) -> void:
	if slot < 0 or slot >= _weapons.size() or not is_instance_valid(_weapons[slot]):
		return
	_weapons[slot].fire()
	last_fired_frame = Engine.get_physics_frames()
	# M1.3: autodebug event stream (no-op unless --sync-log). Fire-attempt, not
	# guaranteed shot (weapon may be on cooldown/reloading); kept uniform across
	# all weapon types by emitting at the single fire chokepoint.
	Game.sync_log_event("fired", name, {"slot": slot})

# Public entry point. Weapons always call this; never call _apply_damage directly.
# SP: runs directly. MP client: routes to server via RPC (peer_id 1).
# `source` is the weapon node that produced the damage; needed for server clamp (V32).
func take_damage(amount: float, source: Node3D = null) -> void:
	# V25 / V30 / V61 (T384): damage exists on the server only. A client never deals any
	# (no weapon fires there, V38; projectiles are ghosts) and has no way to ask for some:
	# the old client->server damage RPC let any connected peer kill any mech.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	request_damage(amount, source)

## Mech that owns `n` (a weapon / projectile source), or null if freed or unowned.
static func _owning_mech(n: Node) -> Node:
	while n != null and is_instance_valid(n) and not n.is_in_group("mechs"):
		n = n.get_parent()
	return n if n != null and is_instance_valid(n) else null

# T96: damage chokepoint; T103 will add server-side validation here.
func request_damage(amount: float, source: Node3D = null) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and source != null:
		# T412: a weapon whose hits vary (arc by range, Patience by charge) states its max_damage
		var max_dmg: float = source.get("max_damage") if "max_damage" in source else (source.get("damage") if "damage" in source else amount)
		var src_range: float = source.get("range") if "range" in source else INF
		if amount > max_dmg * 1.5:
			return
		if is_instance_valid(source) and source is Node3D and not (source is OrbitalStrike):  # T544: it lands at its mark
			var dist: float = (source as Node3D).global_position.distance_to(global_position)
			if dist > src_range * 1.2:
				return
	# T264 damage boost pickup: the shooter's hits count x1.5 (after validation, server side)
	var shooter := _owning_mech(source) if source != null else null
	if shooter != null and float(shooter.get("damage_boost_s")) > 0.0:
		amount *= DAMAGE_BOOST
	if shooter != null and shooter.get("anchored"):  # T430
		amount *= ANCHOR_DAMAGE_OUT
	if shooter != null and float(shooter.get("slow_s")) > 0.0:  # T478: stomped -> weakened
		amount *= STOMP_WEAKEN_K
	_apply_damage(amount, source)

var _last_hurt_sfx := -3

func _apply_damage(amount: float, source: Node3D = null) -> void:
	if health <= 0.0 or invincible:
		return
	if anchored:  # T430: planted, it shrugs off half
		amount *= ANCHOR_DAMAGE_IN
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
	var src_mech := _owning_mech(source)
	if src_mech != null and src_mech.get("team") != team:
		src_mech.damage_dealt_total += actual
		last_attacker = src_mech
	damaged.emit()
	damage_event.emit(actual, source)
	# T360 (HUMAN_FOUND 2026-11-08 late: "Impact sound still plays when hit by arc weapon"): the
	# hurt clank fired on every arc / laser damage tick (~10 a second); weapons that turn the
	# impact sound off (T316: laser, arc, Patience) don't sound it here either
	var quiet: bool = source != null and is_instance_valid(source) and source.get("impact_sound_enabled") == false
	if not quiet and Engine.get_physics_frames() - _last_hurt_sfx >= 3:  # T330: one per blast, not per pellet
		_last_hurt_sfx = Engine.get_physics_frames()
		SoundManager.play_sfx("damage_hit", global_position)
	if OS.is_stdout_verbose():  # T389: one line per hit filled a long-running server's log
		print("[Mech] %s  %.0f / %.0f HP" % [name, health, max_health])
	# M1.3: autodebug event stream. Runs at the server-authoritative damage
	# chokepoint (clients route take_damage -> server via RPC), so hit/died are
	# logged once, on the authoritative peer.
	# M2.1: attribute the shooter. `source` is the weapon node (child of the
	# owning mech), so walk up to the mech for name + team; -1/"" when unknown
	# (source freed, or SP paths that pass null).
	var src_name := ""
	var src_team: int = -1
	if src_mech != null:
		src_name = src_mech.name
		src_team = src_mech.get("team")
	Game.sync_log_event("hit", name, {"amount": snappedf(actual, 0.01), "hp": snappedf(health, 0.01), "src": src_name, "src_team": src_team})
	# B139: hits summing to the health can leave a float sliver (2.7 - 3 x 0.9 = 4e-16): that's dead
	if health <= 0.001:
		health = 0.0
		Game.sync_log_event("died", name, {})
		_die()
		# Audit #11: death must not ride the unreliable _sync_health stream (final
		# packet droppable) -- and clients never ran _die() at all, so dead mechs
		# stayed visible and the client-side squad picker / spectate (T127/T128,
		# both driven by `died`) never triggered. Reliable death RPC fixes all three.
		if multiplayer.has_multiplayer_peer():
			_sync_death.rpc()
	# T474: clients get the health from every snapshot (receive_snapshot); a reliable RPC per hit queued
	# behind ENet's resends (flamer_net@bad: all reliable traffic held 2-5 s behind one lost packet)

# T40: clients receive health updates here (death arrives via _sync_death, reliable).
# B49 (V44): change-driven state -> reliable. Unreliable left a client showing a stale
# HP for 10 s after one lost packet under 1% loss (T151 chaos sweep).
@rpc("authority", "reliable")
func _sync_health(h: float) -> void:
	health = h

# Audit #11: reliable death replication. Runs the same _die() path as the server:
# hides the body, disables collision, plays death SFX/VFX, emits `died` (which
# drives the client-side squad picker T127 / spectate T128), and launches the
# cockpit pod for the local player's own mech.
@rpc("authority", "reliable")
func _sync_death() -> void:
	Game.sync_log_event("died_seen", name, {})  # T555 parity
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
# Reliable per V44: change-driven one-shot, a dropped packet would lose the flash forever.
@rpc("authority", "reliable")
func _sync_hit_confirmed(slot: int) -> void:
	Game.sync_log_event("hit_confirm", name, {"slot": slot})
	if slot >= 0 and slot < _weapons.size() and is_instance_valid(_weapons[slot]):
		_weapons[slot].hit_confirmed.emit()

# B35: reload starts server-side; clients tick a cosmetic timer for the HUD bar.
@rpc("authority", "reliable")
func _sync_reload_started(slot: int) -> void:
	if slot >= 0 and slot < _weapons.size() and is_instance_valid(_weapons[slot]) \
			and _weapons[slot].has_method("start_reload_cosmetic") and not _weapons[slot].is_reloading():
		_weapons[slot].start_reload_cosmetic()  # T512: a snapshot may have started it already

@rpc("authority", "reliable")
func _sync_ammo(slot: int, a: int) -> void:
	if slot >= 0 and slot < _weapons.size() and is_instance_valid(_weapons[slot]):
		_weapons[slot].ammo = a

@rpc("authority", "reliable")
func _sync_shield(pool: float) -> void:
	if _energy_shield != null:
		_energy_shield.set("shield_hp", pool)
		# T373: a sync means a hit landed on the server -- hold the regen as absorb() does there, or the
		# client's copy (now on every peer's HUD) refilled at once and jumped back on the next hit
		_energy_shield.set("_regen_timer", float(_energy_shield.get("regen_delay")))

# T119: called by Arena._rpc_snapshot on clients to push a server transform sample.
func receive_snapshot(entry: Dictionary, local_t: float = -1.0) -> void:
	# B43 (B-h): during a scene change the old Arena is detached but not yet freed and
	# RPCs still reach it; ignore them. (Dictionary.get evaluates its default eagerly,
	# so the global_transform defaults below must only run inside the tree.)
	if not is_inside_tree():
		return
	if _charge and lunging and entry.has("lv") and not _predicting():  # T499: turn losses -> glow / crouch here
		_charge_v0 = float(entry["lv"])
		_charge_l0 = float(entry.get("ll", _charge_l0))  # T513: the level (glow)
	if entry.has("hp") and not is_dead:
		# T474: the health rides every snapshot (newest wins, nothing waits on a resend); a death still
		# comes reliable (_sync_death)
		health = float(entry["hp"])
	# T512 (two_matches@bad reload_desync: the reliable _sync_reload_started held behind a resend, so a
	# client's reload bar started seconds late): each reloading slot's time left rides the snapshot; a
	# slot not reloading here starts (or a running one re-times) from it. Ends stay local (the timer).
	var rl = entry.get("rl")
	if rl is Dictionary:
		for k in rl:
			if typeof(k) == TYPE_INT and k >= 0 and k < _weapons.size() and is_instance_valid(_weapons[k]) \
					and typeof(rl[k]) == TYPE_FLOAT and is_finite(rl[k]) and _weapons[k].has_method("start_reload_cosmetic"):
				if not _weapons[k].is_reloading():
					_weapons[k].start_reload_cosmetic()
				_weapons[k].set("_reload_timer", clampf(float(rl[k]), 0.0, float(_weapons[k].get("reload_time"))))
	# T504 (bot_lock@bad: a client kept a stale red box 3 s -- the reliable _sync_lock_state held behind a
	# resend, B150): the lock state rides every snapshot too; absent = none
	var lk = entry.get("lk")
	if lk is Array and (lk as Array).size() == 2 and lk[0] is String and lk[1] is String:
		locked_target = _find_mech(lk[0])
		lock_eligible_target = _find_mech(lk[1])
	else:
		locked_target = null
		lock_eligible_target = null
	lock_eligible = lock_eligible_target != null
	if _predicting():
		# T205: own mech predicts; the snapshot corrects it. T423: once a tick, the newest only -- after a
		# TCP resend stall a burst of snapshots lands in one frame, and correcting 20% for each stale one
		# compounded the same error several times over
		_recon_entry = entry
		_last_server_pos = entry.get("pos", _last_server_pos)  # snap_to_server may run before the tick
		return
	_snap_buf.append({
		# T150: server send time mapped to the local clock (Arena._rpc_snapshot)
		"time": local_t if local_t >= 0.0 else Time.get_ticks_msec() * 0.001,
		"pos": entry.get("pos", global_position),
		"quat": entry.get("quat", global_transform.basis.get_rotation_quaternion()),
		"vel": entry.get("vel", Vector3.ZERO),
		"torso_y": entry.get("torso_y", torso.rotation.y),
		"pitch": entry.get("pitch", _camera_pitch),  # T329
	})
	if _snap_buf.size() > _SNAP_BUF_MAX:
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
	if Game.prof_on:  # T165: is a death the combat-frame spike?
		var t0 := Time.get_ticks_usec()
		_die_impl()
		Game.prof_add("die", Time.get_ticks_usec() - t0)
		return
	_die_impl()

func _die_impl() -> void:
	is_dead = true
	if _base_fov > 0.0 and camera != null:  # T531: the scope drops on death
		scope_zoom = 1.0
		camera.fov = _base_fov
	# B128: every lock on us goes now -- the killing shot often lands after the shooter's own lock
	# update in the same tick, which left the shooter locked on a corpse for a tick (lock_target
	# oracle; a rocket fired then would home on the wreck)
	for m in get_tree().get_nodes_in_group("mechs"):
		if m != self and m.get("locked_target") == self:
			m.call("_set_locked_target", null)
			m.set("lock_progress", 0.0)
	Game.ai_director_clear_intent(self)
	if OS.is_stdout_verbose():  # T389
		print("[Mech] %s destroyed" % name)
	SoundManager.play_sfx("mech_death", global_position)
	VFX.death_explosion(global_position + Vector3(0, 0.8, 0))
	set_physics_process(false)
	set_process(false)
	# T155 (B63): weapons keep processing after the mech stops; one fired up to death
	# never saw a release, so its loop audio (arc beam, MG) played on, on every peer.
	for w in _weapons:
		if is_instance_valid(w):
			w.on_fire_release()
	$CollisionShape3D.disabled = true
	_launch_cockpit_pod()  # T267: every mech, on every peer (the death RPC runs this on clients)
	visible = false
	died.emit()

# T267: the pilot's canister (scripts/EjectPod.gd) -- was a blue box for human pilots only (T77).
const EjectPod := preload("res://scripts/EjectPod.gd")
var ejected_pod: Node3D = null  # Arena's death camera rides it (T267)

func _launch_cockpit_pod() -> void:
	var pod := EjectPod.new()
	pod.name = "EjectPod_%s" % name
	get_parent().add_child(pod)
	pod.launch(global_position + Vector3(0, 1.8, 0) * global_transform.basis.get_scale().y, hash(name) ^ Time.get_ticks_msec())
	ejected_pod = pod

func make_camera_current() -> void:
	camera.make_current()

func set_input_source(source: Node) -> void:
	_input_source = source
	if source != null and source.has_method("is_human_input") and source.is_human_input():
		Game.set_mouse_captured(true)

func apply_modifier(stat: String, value: float) -> void:
	_modifiers[stat] = value

func remove_modifier(stat: String) -> void:
	_modifiers.erase(stat)

const _MAX_STEP  := 0.37   # slightly above step geometry (0.35m) for margin
const _STEP_RATE := 2.5    # m/s vertical lift speed while stepping up
var _step_up_remaining: float = 0.0

func _physics_process(delta: float) -> void:
	if not Game.prof_on:  # T165 profiling shim
		_physics_process_impl(delta)
		return
	var t0 := Time.get_ticks_usec()
	_physics_process_impl(delta)
	Game.prof_add("mech", Time.get_ticks_usec() - t0)

# ---- T264 pickups: boosts run on every peer (the owner predicts with the speed) ----
const DAMAGE_BOOST := 1.5
const SPEED_BOOST := 1.3
var damage_boost_s := 0.0
var speed_boost_s := 0.0

@rpc("authority", "call_local", "reliable")
func _rpc_boost(kind: String, secs: float) -> void:
	if kind == "damage":
		damage_boost_s = secs
	elif kind == "speed":
		speed_boost_s = secs
		apply_modifier("walk_speed", SPEED_BOOST)
	elif kind == "slow":  # T455/T456: STOMP -- every peer, so the owner's prediction slows too
		slow_s = secs
		apply_camera_shake(STOMP_SHAKE, STOMP_SHAKE_S)  # T478 (user: "Yes" to a shake on stomped players)
	elif kind == "burn":  # T457: the flames on a burning mech (the damage is the server's, ignite)
		burn_s = maxf(burn_s, secs)

func _tick_boosts(delta: float) -> void:
	if _stomp_hit_in >= 0.0:  # T480: the stomp lands at the slam
		_stomp_hit_in -= delta
		if _stomp_hit_in < 0.0:
			_stomp_land()
	if damage_boost_s > 0.0:
		damage_boost_s = maxf(damage_boost_s - delta, 0.0)
	if slow_s > 0.0:
		slow_s = maxf(slow_s - delta, 0.0)
	_tick_burn(delta)
	if speed_boost_s > 0.0:
		speed_boost_s = maxf(speed_boost_s - delta, 0.0)
		if speed_boost_s == 0.0:
			remove_modifier("walk_speed")

## T264 ammo pickup: every weapon full, any reload finished (server; ammo syncs to clients).
func refill_ammo() -> void:
	for w in get_weapons():
		if int(w.get("max_ammo")) >= 0:
			w.set("ammo", w.get("max_ammo"))
		w.set("_reloading", false)
		w.set("_reload_timer", 0.0)
		if "max_charge_time" in w:  # T495 (HUMAN_FOUND 2026-11-18: "Ammo powerup should fully charge Patience.")
			w.set("_charge_time", float(w.get("max_charge_time")))

## T374: below this a mech has left the world (every map's floor is far above): the server
## destroys it, so a match never hangs on a mech falling forever.
const FALL_KILL_Y := -60.0

func _physics_process_impl(delta: float) -> void:
	_tick_boosts(delta)
	if global_position.y < FALL_KILL_Y and not is_dead and (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()):
		_apply_damage(1e9)
	# V38: non-server peers skip all local simulation; transforms driven by snapshot interp.
	# T205: except the client's own mech, which predicts its movement (V37).
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_tick_ability_timers_client(delta)  # T468
		if _predicting():
			if not _recon_entry.is_empty():  # T423: the newest snapshot since the last tick
				_reconcile(_recon_entry)
				_recon_entry = {}
			_handle_look()
			_handle_wheel()
			_maybe_forward_input()
			if _pred_live and get_meta("staged", false):
				# T519 (user: a client's first mech "could still move and look" but not shoot or use its
				# ability; start_pick_timeout: it fell out of the world): a mech staged for its pilot's start
				# pick used to have its collision off -- the owner's prediction fell through the floor while
				# the server held it in the air (T374). Now both let it settle on the floor and nothing else
				# (Arena._stage keeps its mask), recording where it is.
				_staged_settle(delta)
				_pred_record()
			elif _pred_live:
				if not is_on_floor() and _step_up_remaining <= 0.0:
					velocity += get_gravity() * delta
				if _pred_held:  # T472: stopped like the server, until it moves again
					velocity.x = 0.0
					velocity.z = 0.0
				else:
					_handle_movement(delta)
				_slide(delta)
				_pred_record()
			_update_legs(delta)
			return
		_apply_snapshot_interp()
		_lunge_visual_tick(delta)  # T342 / T473: pose + glow only
		if _input_source != null and owner_peer_id == multiplayer.get_unique_id():
			_handle_look()   # camera still tracks local mouse
			_handle_wheel()
			_maybe_forward_input()
		_update_legs(delta)
		return
	# T162 (B51): an MP server holds every mech (players and bots) until all clients
	# have loaded the match (Game.mp_live, V52) -- no head start for the host.
	if not Game.mp_live and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		return
	# T374: a first mech staged for its pilot's start pick (T279) has its collision off; a dedicated
	# server doesn't pause for the pick, so gravity sank it through the floor -- into FALL_KILL_Y on
	# a slow pick. It waits where it stands.
	if get_meta("staged", false):
		_staged_settle(delta)  # T519: stands on the floor, nothing else
		return

	if not is_on_floor() and _step_up_remaining <= 0.0:
		velocity += get_gravity() * delta

	if _input_source != null:
		_handle_look()
		_handle_wheel()
		_handle_movement(delta)
		_handle_slot_toggle()
		_handle_reload()
		_handle_fire()
		_handle_ability()
		if _input_source.has_method("is_human_input") and _input_source.is_human_input():
			_update_lock(delta)
		elif has_lock_weapon():
			_update_lock(delta)  # T169: bots lock through the same system (V15) so rockets/arc fire

	if multiplayer.has_multiplayer_peer():
		_broadcast_ammo_changes()

	_slide(delta)
	if owner_peer_id > 0 and owner_peer_id != multiplayer.get_unique_id():
		input_ack_ticks += 1  # T205: ticks on the newest input, for the owner's reconciliation
	_update_legs(delta)

# Step-up + move_and_slide: the server's simulation and the owner's prediction (T205).
func _slide(delta: float) -> void:
	_try_step_up()
	if _step_up_remaining > 0.0:
		var lift := minf(_step_up_remaining, _STEP_RATE * delta)
		position.y += lift
		_step_up_remaining -= lift
	move_and_slide()
	_try_step_up_from_collisions()
	_lunge_contacts()  # T342

# ---- T205: client-side prediction of the own mech ----
# The owning client moves its mech from local input every tick (same code as the
# server) and records where each tick left it, labelled (input seq, n-th tick on it).
# Each snapshot carries the server's position after `ackt` ticks on input `ack`; the
# client compares that with its own record for the same (seq, tick), then eases the
# difference out (PRED_BLEND per snapshot) or snaps when it is over PRED_SNAP_M.
# Matching the tick count matters: the server runs a packet for ~2 ticks, varying with
# jitter, and comparing against the wrong tick reads as a constant pull backwards.
# Fire, abilities, damage stay server-only (V38); the jump's launch is replayed here
# when the server's activation arrives.
const PRED_SNAP_M := 1.0      # calibration knob: snap instead of easing above this
const PRED_BLEND := 0.2       # share of the error removed per snapshot (20 Hz)
const PRED_DEADZONE := 0.02   # m: below this it's float noise, leave it
const PRED_HELD_M := 0.3      # T472: a server that has the mech stopped and this far off -> stop here too (calibration knob)
var _pred_held := false       # T472: the server has us stopped where the prediction slid on
const _PRED_HIST_MAX := 120   # 2 s of ticks
var _pred_live := false       # first snapshot seen (the server holds mechs until live)
var _pred_synced := false     # first record matched: timelines aligned
var _pred_hist: Array = []    # [seq, n-th tick on it, position after the tick]

func _predicting() -> bool:
	return _input_source != null and owner_peer_id == multiplayer.get_unique_id() and not is_dead

func _pred_record() -> void:
	var n := 1
	if not _pred_hist.is_empty() and int(_pred_hist[-1][0]) == _net_input_seq:
		n = int(_pred_hist[-1][1]) + 1
	_pred_hist.append([_net_input_seq, n, global_position])
	if _pred_hist.size() > _PRED_HIST_MAX:
		_pred_hist.pop_front()

# T270: the newest server position of our predicted mech (see snap_to_server)
var _last_server_pos := Vector3.INF
var _recon_entry: Dictionary = {}  # T423: the newest snapshot entry for our predicted mech, reconciled next tick

## T270: at match end the server froze every mech, but on a lossy link its match-end RPC
## lands late and this client predicted on meanwhile -- inputs the server never applied --
## and no snapshot follows to correct it (the stream stops at match end): the own mech
## froze up to ~1.7 m off (dedicated_server@bad transform_desync). Take the server's word.
func snap_to_server() -> void:
	if _predicting() and _last_server_pos != Vector3.INF:
		global_position = _last_server_pos
		velocity = Vector3.ZERO

func _reconcile(entry: Dictionary) -> void:
	var server_pos: Vector3 = entry.get("pos", global_position)
	_last_server_pos = server_pos
	if not _pred_live:  # start from the server's word (mid-fall from the spawn height, too)
		_pred_live = true
		global_position = server_pos
		velocity = entry.get("vel", velocity)
		return
	var ack: int = int(entry.get("ack", -1))
	var ackt: int = int(entry.get("ackt", 0))
	if ack <= 0 or ackt <= 0:
		return
	var i := -1
	for k in range(_pred_hist.size() - 1, -1, -1):
		var h: Array = _pred_hist[k]
		if int(h[0]) == ack and (int(h[1]) <= ackt or i < 0):
			i = k  # the record for tick ackt on input ack (or its last tick if the server ran longer)
			if int(h[1]) <= ackt:
				break
		elif int(h[0]) < ack:
			break
	if i < 0:
		return  # older than the history, or not sent yet
	# a packet that lands a tick late makes the server run the previous input one tick
	# longer (and this one a tick shorter): same total ticks, so a neighbour record is
	# the true match -- take the closest of the three
	for k in [i - 1, i + 1]:
		if k >= 0 and k < _pred_hist.size() and server_pos.distance_to(_pred_hist[k][2]) \
				< server_pos.distance_to(_pred_hist[i][2]):
			i = k
	_lunge_sync(entry, _pred_hist.size() - 1 - i)  # B131
	var err: Vector3 = server_pos - (_pred_hist[i][2] as Vector3)
	if not _pred_synced:
		# The first snapshot (the starting point) was already up to a round trip old; the
		# server kept moving meanwhile, so the first matched record trails it by about
		# speed x latency. Take that whole difference once: it's alignment, not error.
		_pred_synced = true
		# T429 (B143): the height part moves through collision. Mid-fall at spawn the matched
		# record was still in the air while the server had landed: the whole err sank a
		# landed client 0.8 m into the platform (Godot Physics: stuck ~17 ticks; Jolt: fell through).
		var before := global_position
		global_position += Vector3(err.x, 0.0, err.z)
		move_and_collide(Vector3(0.0, err.y, 0.0))
		var shift := global_position - before
		for k in range(i, _pred_hist.size()):
			_pred_hist[k][2] = (_pred_hist[k][2] as Vector3) + shift
		_pred_hist = _pred_hist.slice(i)
		return
	# T472: the server has the mech STOPPED (head-on into a wall-end / pillar pocket on Math Temple: contact
	# normal . desired = -0.99) while this prediction, ~1 cm off, slid on around the obstacle: easing 20% a
	# snapshot while still walking let the error grow for ~2 s to a 0.9 m snap-back (and snapping each time
	# only re-slid it: jitter). A stopped server and a real divergence (records are matched by input tick, so
	# latency doesn't inflate err) -> stop walking here too until the server moves again; the error eases out.
	var srv_v: Vector3 = entry.get("vel", Vector3.ONE)
	var srv_still := Vector2(srv_v.x, srv_v.z).length() < 0.05
	if srv_still and err.length() > PRED_HELD_M:
		_pred_held = true
	elif not srv_still:
		_pred_held = false
	var snap := err.length() > PRED_SNAP_M
	var corr: Vector3 = err if snap else err * PRED_BLEND
	if snap:
		velocity = entry.get("vel", velocity)
	if err.length() >= PRED_DEADZONE:  # on the error: a small steady offset still eases out
		global_position += corr
		for k in range(i, _pred_hist.size()):
			_pred_hist[k][2] = (_pred_hist[k][2] as Vector3) + corr
	_pred_hist = _pred_hist.slice(i)  # keep the match: the next snapshot's tick-early neighbour
	Game.sync_log_event("pred_recon", name, {"err": snappedf(err.length(), 0.001), "snap": snap})

# T197 (B84): no step-up while launching upward. The jump sets velocity.y in the same tick,
# before this runs; a rise ahead (slope, step) passed the shin/clear ray test and the
# step-up zeroed velocity.y -- the jump became a 0.37 m step.
const _JUMPING_VY := 0.5

func _try_step_up() -> void:
	if velocity.y > _JUMPING_VY:
		return
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
	if _step_up_remaining > 0.0 or velocity.y > _JUMPING_VY:
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

## T519: a staged mech (start pick) only settles onto the floor: no input, no horizontal motion.
func _staged_settle(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y + get_gravity().y * delta
	move_and_slide()

func _update_legs(delta: float) -> void:
	if not Game.prof_on:  # T165 profiling shim (T525: legs inside "mech")
		_update_legs_impl(delta)
		return
	var t0 := Time.get_ticks_usec()
	_update_legs_impl(delta)
	Game.prof_add("legs", Time.get_ticks_usec() - t0)

func _update_legs_impl(delta: float) -> void:
	# T174: airborne legs tuck. Simulating peers ask physics; an MP client runs no physics
	# for any mech (snapshot interp, V38), so it probes for ground under the feet.
	var airborne: bool
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.3,
			global_position + Vector3.DOWN * 0.4)
		q.exclude = get_exclude_rids()
		airborne = get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	else:
		airborne = not is_on_floor() and _step_up_remaining <= 0.0
	_anchor_pose = move_toward(_anchor_pose, ANCHOR_CROUCH if anchored else 0.0, 4.0 * delta)
	var pose := lunge_pose()
	if pose == Vector3.ZERO and _anchor_pose > 0.0:
		pose = Vector3(_anchor_pose, 0.0, 0.0)
	var lift := 0.0
	if _stomp_t > 0.0:  # T456 / T480: rear up, slam, settle into a crouch
		var was := _stomp_t
		_stomp_t = maxf(0.0, _stomp_t - delta)
		var e := STOMP_POSE_S - _stomp_t  # time since the stomp began
		if e < STOMP_RAISE_S:
			lift = sin(0.5 * PI * e / STOMP_RAISE_S)  # eases up
		elif e < STOMP_RAISE_S + STOMP_SLAM_S:
			lift = 1.0 - (e - STOMP_RAISE_S) / STOMP_SLAM_S  # slams down
		else:
			if pose == Vector3.ZERO:
				var k := (e - STOMP_RAISE_S - STOMP_SLAM_S) / STOMP_SETTLE_S
				pose = Vector3(STOMP_CROUCH * sin(PI * clampf(k, 0.0, 1.0)), 0.0, 0.0)
		if STOMP_POSE_S - was < STOMP_RAISE_S + STOMP_SLAM_S and e >= STOMP_RAISE_S + STOMP_SLAM_S:
			_stomp_ring()  # the foot is down
	legs.set("stomp_lift", lift)
	legs.call("update_gait", gait_velocity(), global_transform.basis, leg_rotation_speed, walk_speed, delta, airborne,
		pose)

## T454 (user 2026-11-17: Swift's "legs just look funny while dashing"): a dash doesn't step -- at
## 20 m/s the gait spun the stride and swung the hips round to a sideways dash and back. The legs
## see a standstill (no stepping, no turning) and hold DASH's braced crouch while the body skims.
func gait_velocity() -> Vector3:
	return Vector3.ZERO if lunging and _dash else velocity

# T150 (B48) / V37: render remote AND own mechs INTERP_DELAY behind the newest
# server state, interpolating between the two buffered snapshots around that
# moment. Was: a 2-snapshot buffer rendered 100 ms back, which always clamped to
# the older snapshot -> no interpolation, 20 Hz steps (mechs stood still 2 of 3
# ticks). Gaffer: delay >= 3 x snapshot interval (20 Hz -> 150 ms) survives one
# lost packet plus jitter. Buffer starved -> T423: run on from the newest (below).
const INTERP_DELAY := 0.15   # s -- calibration knob (T150 measured, see SPEC B48)
## T423 (WebSocket since T422): a lost TCP segment holds every snapshot behind it for a resend (~RTT + 0.2 s),
## so the buffer runs dry and remote mechs froze, then jumped (kill_confirm@bad: still on 26% of the ticks
## they moved). Starved, a mech walks on along its newest velocity, flat (gravity and slopes are the next
## snapshot's job), for at most this long -- past it the link is really gone, so it holds.
## ponytail: straight-line guess; a mech that turned in the stall lands off-line and steps back when data comes.
const EXTRAP_MAX_S := 0.5
const _SNAP_BUF_MAX := 8     # 400 ms of 20 Hz snapshots

func _apply_snapshot_interp() -> void:
	if _snap_buf.is_empty():
		return
	var render_t := Time.get_ticks_msec() * 0.001 - INTERP_DELAY
	# Drop snapshots entirely behind render_t, keeping the one at/just before it.
	while _snap_buf.size() >= 2 and (_snap_buf[1]["time"] as float) <= render_t:
		_snap_buf.pop_front()
	var interp_torso_y: float = torso.rotation.y
	var interp_pitch: float = _camera_pitch
	# B40: Basis(quat) carries no scale; keep the body_scale Arena set at spawn, or
	# every client draws (and aims from) every mech at scale 1.
	var body_scale := global_transform.basis.get_scale()
	var s0: Dictionary = _snap_buf[0]
	if _snap_buf.size() == 1 or render_t <= (s0["time"] as float):
		# Starved (render_t past the newest): T423 run on along its velocity; still filling (render_t before
		# the oldest): hold s0.
		var run_on: float = clampf(render_t - (s0["time"] as float), 0.0, EXTRAP_MAX_S)
		var v0: Vector3 = s0["vel"] as Vector3
		global_transform = Transform3D(Basis(s0["quat"] as Quaternion).scaled(body_scale),
			(s0["pos"] as Vector3) + Vector3(v0.x, 0.0, v0.z) * run_on)
		velocity = s0["vel"] as Vector3
		interp_torso_y = s0.get("torso_y", torso.rotation.y)
		interp_pitch = s0.get("pitch", _camera_pitch)
	else:
		var s1: Dictionary = _snap_buf[1]
		var span: float = (s1["time"] as float) - (s0["time"] as float)
		var t: float = clampf((render_t - (s0["time"] as float)) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		global_transform = Transform3D(
			Basis((s0["quat"] as Quaternion).slerp(s1["quat"] as Quaternion, t)).scaled(body_scale),
			(s0["pos"] as Vector3).lerp(s1["pos"] as Vector3, t))
		velocity = (s0["vel"] as Vector3).lerp(s1["vel"] as Vector3, t)
		interp_torso_y = lerp_angle(
			s0.get("torso_y", torso.rotation.y) as float,
			s1.get("torso_y", torso.rotation.y) as float, t)
		interp_pitch = lerpf(s0.get("pitch", _camera_pitch) as float, s1.get("pitch", _camera_pitch) as float, t)
	if owner_peer_id != multiplayer.get_unique_id():
		torso.rotation.y = interp_torso_y
		_camera_pitch = interp_pitch  # T329: a remote mech's guns tilt with its aim

var _intent_firing := false  # T555: the last fire state logged as intent

func _maybe_forward_input() -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.is_server():
		return
	if owner_peer_id != multiplayer.get_unique_id():
		return
	# T158 (B39): a press lasts ONE tick (is_action_just_pressed) but packets go out
	# every 2nd tick, so sample every tick into cumulative counts. The counts ride
	# every packet (V47: absolute, latest wins), so a lost packet can't lose a press.
	# T555: what this pilot (player or bot) asked for, for the agency oracle -- logged here, on the
	# owning client, for every input source; no-op unless the session is recorded
	if _input_source.is_reload_pressed():
		_press_counts[0] += 1
		Game.sync_log_event("intent", name, {"action": "reload", "slot": -1})
	if _input_source.is_ability_pressed():
		_press_counts[1] += 1
		Game.sync_log_event("intent", name, {"action": "ability", "slot": -1})
	var st: int = _input_source.get_slot_toggle()
	if st >= 0 and st < 4:
		_press_counts[2 + st] += 1
		Game.sync_log_event("intent", name, {"action": "slot", "slot": st})
	var firing: bool = _input_source.is_firing_primary() or (_input_source.is_firing_secondary() and _active_set.has(true))
	if firing != _intent_firing:
		_intent_firing = firing
		Game.sync_log_event("intent", name, {"action": "fire", "on": firing})
	_net_input_tick += 1
	if _net_input_tick % 2 != 0:
		return
	var payload := {
		"move": _input_source.get_move_direction(),
		"aim": Vector2(torso.rotation.y, _camera_pitch),  # V47: absolute, latest wins
		"shoulder": shoulder,  # T196/B83: the server offsets its copy of our camera the same
		"fire_prim": _input_source.is_firing_primary(),
		"fire_sec": _input_source.is_firing_secondary(),
		"presses": _press_counts.duplicate(),
		"lob": lob_range,  # T532
		"tr": tracers_on,  # T551
	}
	if not multiplayer.get_peers().has(1) or not Game.server_heard:
		return  # T206: a late joiner's Arena runs a few ticks before its handshake completes; B101: and
		# we're connected before the server is (B89 order) -- wait for its first snapshot
	_net_input_seq += 1
	rpc_id(1, &"_rpc_input", _net_input_seq, payload)

@rpc("any_peer", "unreliable_ordered")
func _rpc_input(seq: int, payload: Dictionary) -> void:
	if not is_inside_tree():
		return  # B77: a straggler resolved via the node cache to a mech already leaving the tree
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != owner_peer_id:
		Game.net_refuse(sender, "_rpc_input: not its mech")
		return
	last_input_ms = Time.get_ticks_msec()
	Game._stream_peers[sender] = true  # T511: its input comes from this match's Arena -> stream to it
	var sh = payload.get("shoulder", shoulder)
	if typeof(sh) == TYPE_FLOAT and is_finite(sh):
		shoulder = 0.0 if absf(sh) < 0.5 else signf(sh)  # V41: only ever -1 / 0 (center, T252) / +1
	var lb = payload.get("lob")
	if typeof(lb) == TYPE_FLOAT and is_finite(lb):
		lob_range = clampf(lb, -1.0, 1000.0)  # T532 / V41: Mortar clamps it to its own range again
	var trc = payload.get("tr")
	if typeof(trc) == TYPE_BOOL:
		tracers_on = trc  # T551 / V41: a bool only; tracers_active() still wants the skill
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
	if seq != input_ack:  # T205 (unreliable_ordered: newer only)
		input_ack = seq
		input_ack_ticks = 0
	_input_source.push_input(payload)

## T532: the wheel / up-down arrows step the mortar's range (only while a mortar is mounted).
## T551: Tracer Rounds -- the pilot's T toggle (tracers_on) and whether this mech's shots carry tracers now.
var tracers_on := false

func tracers_active() -> bool:
	return tracers_on and skill("tracer_rounds") > 0.0

func _handle_tracer_toggle() -> void:
	if _input_source == null or not _input_source.is_tracer_toggle_pressed():
		return
	if skill("tracer_rounds") <= 0.0:
		return  # not owned: T does nothing
	tracers_on = not tracers_on
	var hud: Node = get_tree().current_scene.get("hud") if get_tree().current_scene != null else null
	if hud != null and hud.has_method("tracer_notice"):
		hud.call("tracer_notice", tracers_on)

func _handle_wheel() -> void:
	_handle_tracer_toggle()  # T551: polled with the wheel -- the local pilot's per-tick UI input, every mode
	var w: float = _input_source.get_wheel() if _input_source.has_method("get_wheel") else 0.0
	if w == 0.0:
		return
	for wpn in _weapons:
		if wpn is Mortar:
			lob_range = (wpn as Mortar).step_range(lob_range, w)
			return
	var top := 1.0 + skill("scope_zoom")
	if top <= 1.0 or camera == null:
		return
	for wpn in _weapons:
		# user 2026-11-20: "It should work on laser, too, and any other weapon with a range over 150m."
		# T535 (user: "Long-range nonlinear lock-on weapons don't need zoom, and it might be distracting.")
		if wpn is LaserCannon or (float(wpn.get("range")) > SCOPE_RANGE_M and not wpn.get("requires_lock") \
				and not (wpn is OrbitalStrike)):  # T547: no lock now, still no scope (it aims on the minimap)
			if _base_fov <= 0.0:
				_base_fov = camera.fov
			# T545 (user: "steps ... too big at the beginning and good near max"): a constant FACTOR a notch
			scope_zoom = clampf(scope_zoom * pow(SCOPE_STEP, w), 1.0, top)
			camera.fov = _base_fov / scope_zoom
			return

func _handle_look() -> void:
	# V47 (B38): a remote client's aim arrives absolute; apply it as-is. Deltas over
	# the lossy _rpc_input channel lost rotation for good, and the server scaled them
	# by its OWN sensitivity -> server aim drifted from what the client saw.
	if _input_source.has_method("get_abs_aim"):
		var aim = _input_source.get_abs_aim()
		if aim != null:
			torso.rotation.y = aim.x
			_camera_pitch = clampf(aim.y, -1.2, 0.4)
		return
	var look: Vector2 = _input_source.get_look_delta()
	if look == Vector2.ZERO:
		return
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003) / scope_zoom  # T531
	torso.rotate_y(-look.x * sens)
	_camera_pitch = clamp(_camera_pitch - look.y * sens, -1.2, 0.4)
	# camera_arm.rotation.x is owned by _process (shake + pitch combined)

func _handle_movement(delta: float) -> void:
	if _lunge_step(delta):  # T342 / T473: a charge (or dash) drives the motion, no steering
		return
	if anchored:  # T430: feet planted -- stops dead, still turns and aims
		_desired_move_dir = Vector3.ZERO
		velocity.x = 0.0
		velocity.z = 0.0
		return
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
		Game.sync_log_event("input_applied", name, {"action": "slot", "slot": idx})  # T158
		toggle_weapon_slot(idx)

func _handle_reload() -> void:
	if not _input_source.is_reload_pressed():
		return
	Game.sync_log_event("input_applied", name, {"action": "reload", "slot": -1})  # T158
	for weapon in _weapons:
		if is_instance_valid(weapon) and weapon.has_method("try_reload"):
			weapon.try_reload()

# T168: lock tolerance is a world-space radius around the target's centre, not an angle,
# so the cone widens naturally as the target gets closer (B22) and stays tight far away.
# Metres per unit of target body scale (capsule is 1 m wide x 2 m tall at scale 1).
const _LOCK_ACQ_M  := 2.5   # acquire: crosshair ray passes within this of the target centre
const _LOCK_HOLD_M := 5.0   # hold once locked (hysteresis)
# T408 (HUMAN_FOUND: the reticle box: "There should be no max distance at which it appears"): the
# eligible box searches as far as a camera sees; a lock still builds only within lock_weapon_range (T334)
const _LOCK_RANGE  := 5000.0

## Crosshair-ray miss distance to target's centre in target-scale units; INF if behind camera.
func _lock_miss(target: Node3D, cam_pos: Vector3, cam_fwd: Vector3) -> float:
	var to: Vector3 = (target.call("center_mass") if target.has_method("center_mass") else target.to_global(Vector3.UP)) - cam_pos  # T319
	var along := to.dot(cam_fwd)
	if along <= 0.0:
		return INF
	return (to - cam_fwd * along).length() / target.global_transform.basis.get_scale().x

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
		if _lock_miss(_lock_candidate as Node3D, cam_pos, cam_fwd) <= _LOCK_HOLD_M:
			candidate = _lock_candidate

	if candidate == null:
		var best_cos := -1.0
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
			if _lock_miss(mech3d, cam_pos, cam_fwd) > _LOCK_ACQ_M:
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
		# B47 (B-e): the red aim box (eligible target) is drawn for every loadout, so
		# broadcast it here too -- this early return used to skip the broadcast below.
		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			_broadcast_lock_state()
		return
	# T334 (HUMAN_FOUND 2026-11-05: "All lock-on weapons should not lock on until the weapon is
	# within range. Square reticle should still be visible at any range."): the red box above
	# (lock_eligible) stays; the lock itself only builds within a lock weapon's range.
	if candidate != null and global_position.distance_to(candidate.global_position) > lock_weapon_range():
		candidate = null
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
		rpc_fx(self, &"_sync_lock_progress", [lock_progress])  # T462

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
	_tick_charges(delta)
	for key in _ability_active_timers.keys():
		if _ability_active_timers[key] > 0.0:
			_ability_active_timers[key] = maxf(0.0, _ability_active_timers[key] - delta)
			if _ability_active_timers[key] == 0.0:
				_deactivate_ability(key)
	if field_repair:
		_field_repair_tick(delta)
	if not _input_source.is_ability_pressed():
		return
	Game.sync_log_event("input_applied", name, {"action": "ability", "slot": -1})  # T158
	for ability in _abilities:
		if ability.trigger != 0:
			continue
		var key: String = ability.effect_key
		if key == "charge":
			_charge_press()  # T473: a toggle, no recharge
			return
		if _ability_cooldowns.get(key, 0.0) > 0.0:
			return
		if _ability_active_timers.get(key, 0.0) > 0.0:
			return
		if lunging and key == "dash":
			return  # T454: a second dash charge mid-dash would restart it (the first one's ground lost)
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
			# B75: T178 leaves the default Waist/Body/Head nodes mesh-less (kit boxes replace
			# them); a surface override on an empty MeshInstance is an engine error. B111: so is
			# one on a mesh with no surfaces yet (T259's arc bolt before its first draw).
			if mesh is MeshInstance3D and mesh.mesh != null and mesh.mesh.get_surface_count() > 0:
				var saved: Array = []  # T528: every surface (the skinned kit body has one per material)
				for s in mesh.mesh.get_surface_count():
					saved.append(mesh.get_surface_override_material(s))
					mesh.set_surface_override_material(s, mat)
				_stealth_saved_mats[mesh] = saved
	else:
		for mesh in all_meshes:
			if mesh is MeshInstance3D and _stealth_saved_mats.has(mesh):
				var saved: Array = _stealth_saved_mats[mesh]
				for s in mini(saved.size(), mesh.mesh.get_surface_count() if mesh.mesh != null else 0):
					mesh.set_surface_override_material(s, saved[s])
		_stealth_saved_mats.clear()

const JUMP_HEAL := 40.0  # T372 (user 2026-11-09: keep the 16 s cooldown, halve the heal; was 80)

func _activate_ability(ability: Resource) -> void:
	match ability.effect_key:
		"jump_heal":
			_jump_launch()
			health = minf(health + JUMP_HEAL, max_health)
		"stealth":
			is_stealthy = true
			_apply_stealth_visual(true)
		"anchor":
			anchored = true
		"field_repair":
			_set_field_repair(true)
		"stomp":
			_stomp()
			_stomp_fx()
		"charge":
			_charge_press()  # T473: no recharge, no activation
			return
		"dash":
			_lunge_begin(_dash_dir())
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				# the owner lines its prediction up on the tick this input ran (T205)
				_rpc_lunge.rpc(input_ack, input_ack_ticks + 1, _lunge_dir, 0.0)
	if ability.duration > 0.0:
		_ability_active_timers[ability.effect_key] = ability.duration
	else:
		var cd: float = _spend_charge(ability, ability_cooldown(ability))  # T454 charges, T468 shared with clients
		_ability_cooldowns[ability.effect_key] = cd
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var slot := _abilities.find(ability)
		if slot >= 0:
			Game.sync_log_event("ability_on", name, {"slot": slot, "key": ability.effect_key})  # T555 parity / agency
			_rpc_ability_activated.rpc(slot)

## The recharge after a use (or after a duration ability ends), the pilot's skill off (T332).
func ability_cooldown(ability: Resource) -> float:
	return ability.cooldown * maxf(0.0, 1.0 - skill("ability_recharge") * ability.recharge_skill_k)  # T332, T454

## T454: one charge recharging at a time, the next right after; the cooldown shows 0 while any is
## left. Server, and (T468) a client's HUD copies.
func _tick_charges(delta: float) -> void:
	for key in _ability_charges.keys():
		var ch: Array = _ability_charges[key]
		if int(ch[0]) < int(ch[2]):
			ch[1] = float(ch[1]) - delta
			if float(ch[1]) <= 0.0:
				ch[0] = int(ch[0]) + 1
				ch[1] = float(ch[1]) + float(ch[3]) if int(ch[0]) < int(ch[2]) else 0.0
		_ability_cooldowns[key] = 0.0 if int(ch[0]) > 0 else float(ch[1])

## T454: spend one charge of `ability` (if it has charges): a recharge of `cd` starts now unless one
## is already running; returns the cooldown to show (0 while charges are left). Server + client copies.
func _spend_charge(ability: Resource, cd: float) -> float:
	var ch: Array = _ability_charges.get(ability.effect_key, [])
	if ch.is_empty():
		return cd
	ch[0] = int(ch[0]) - 1
	ch[3] = cd
	if float(ch[1]) <= 0.0:
		ch[1] = cd
	return 0.0 if int(ch[0]) > 0 else float(ch[1])

# T468 (HUMAN_FOUND 2026-11-18: "Client hud doesn't show ability recharge"): only the server runs the
# ability timers (V38); a client keeps its own copies for the HUD -- started by the ability RPCs,
# ticked here, never acting on anything (the server's RPCs still turn abilities off).
func _tick_ability_timers_client(delta: float) -> void:
	for key in _ability_cooldowns.keys():
		if not _ability_charges.has(key):  # a charges ability's cooldown comes from its charges
			_ability_cooldowns[key] = maxf(0.0, float(_ability_cooldowns[key]) - delta)
	_tick_charges(delta)  # T454 x T468
	for key in _ability_active_timers.keys():
		var left: float = float(_ability_active_timers[key])
		if left <= 0.0:
			continue
		_ability_active_timers[key] = maxf(0.0, left - delta)
		if _ability_active_timers[key] == 0.0:  # ran out here: the recharge shows now, the RPC corrects it
			for a in _abilities:
				if a.effect_key == key:
					_ability_cooldowns[key] = ability_cooldown(a)

func _deactivate_ability(key: String) -> void:
	match key:
		"stealth":
			is_stealthy = false
			_apply_stealth_visual(false)
		"anchor":
			anchored = false
		"field_repair":
			_set_field_repair(false)
	for ability in _abilities:
		if ability.effect_key == key:
			_ability_cooldowns[key] = ability_cooldown(ability)
			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				_rpc_ability_deactivated.rpc(_abilities.find(ability))
			break

# ---- T457: burning (Flamer) ----
# A flamer's hit sets the target alight: the server deals `dps` for `secs` after (refreshed while it
# stays in the flame), straight to health so the gun's range check (request_damage) can't drop it
# once the target walks out of reach; kill credit stays with the gun. Every peer shows a few flames
# on it (_rpc_boost "burn", re-sent every BURN_SYNC_TICKS while it's refreshed).
const BURN_SYNC_TICKS := 30
var burn_s := 0.0
var _burn_dps := 0.0
var _burn_src: Node3D
var _burn_sync_frame := -1000
var _burn_fx: CPUParticles3D

func ignite(secs: float, dps: float, source: Node3D) -> void:
	if health <= 0.0 or is_dead:
		return
	_burn_dps = dps if burn_s <= 0.0 else maxf(_burn_dps, dps)
	_burn_src = source
	burn_s = maxf(burn_s, secs)
	if Engine.get_physics_frames() - _burn_sync_frame >= BURN_SYNC_TICKS:
		_burn_sync_frame = Engine.get_physics_frames()
		rpc(&"_rpc_boost", "burn", secs)

func _tick_burn(delta: float) -> void:
	if burn_s <= 0.0:
		if _burn_fx != null and _burn_fx.emitting:
			_burn_fx.emitting = false
		return
	burn_s = maxf(burn_s - delta, 0.0)
	if (not multiplayer.has_multiplayer_peer() or multiplayer.is_server()) and _burn_dps > 0.0:
		_apply_damage(_burn_dps * delta, _burn_src if is_instance_valid(_burn_src) else null)
	if _burn_fx == null and DisplayServer.get_name() != "headless":
		_burn_fx = CPUParticles3D.new()
		_burn_fx.amount = 16
		_burn_fx.lifetime = 0.5
		_burn_fx.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		_burn_fx.emission_sphere_radius = 0.7
		_burn_fx.direction = Vector3.UP
		_burn_fx.spread = 20.0
		_burn_fx.gravity = Vector3(0, 3.0, 0)
		_burn_fx.initial_velocity_min = 0.5
		_burn_fx.initial_velocity_max = 1.5
		_burn_fx.scale_amount_min = 0.25
		_burn_fx.scale_amount_max = 0.45
		var ramp := Gradient.new()
		ramp.set_color(0, Color(1.0, 0.8, 0.3, 0.9))
		ramp.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
		_burn_fx.color_ramp = ramp
		var q := QuadMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		q.material = m
		_burn_fx.mesh = q
		_burn_fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_burn_fx.position = Vector3(0, 1.4, 0)
		add_child(_burn_fx)
	if _burn_fx != null and not _burn_fx.emitting:
		_burn_fx.emitting = true

# ---- T456: Etna STOMP (effect_key "stomp", instant) ----
# User 2026-11-17: "add as many mechs as you think are good" -- no heavy won a close brawl. The
# server hits every living enemy within STOMP_R: STOMP_DMG at its feet falling to half at the edge
# (take_damage: shields and the kill feed as any hit), and slows it to STOMP_SLOW_K speed for
# STOMP_SLOW_S (_rpc_boost "slow", call_local: the stomped owner's prediction slows with it). No
# knockback (Jolt + prediction). Every peer sees a shockwave ring and the crouch. Calibration knobs.
const STOMP_R := 12.0
const STOMP_DMG := 80.0
const STOMP_FALLOFF := 0.5       # share of STOMP_DMG lost at the edge
const STOMP_SLOW_K := 0.5
const STOMP_SLOW_S := 10.0  # T478 (user: "length 10s (and increase Slow duration)"; was 3)
# T478 (user 2026-11-18, on "How expensive would making Etna's stomp suppress opponents' damage be?":
# "Amount good, length 10s ... flamer burn is good."): a stomped mech's hits deal x STOMP_WEAKEN_K
# for as long as it's slowed (one timer, slow_s); a burn it already set keeps its damage.
const STOMP_WEAKEN_K := 0.6
const STOMP_SHAKE := 0.06    # rad, the stomped player's camera (recoil shakes are 0.001-0.03)
const STOMP_SHAKE_S := 0.6
const STOMP_CROUCH := 0.6
# T480 (user 2026-11-18: "put a stomp animation if there's none already" / "Make it the right leg."): the
# right leg rears up over STOMP_RAISE_S and slams down over STOMP_SLAM_S -- the shockwave, the damage and
# the slow land at the slam (every peer runs the same clock from the ability RPC); then the crouch settles.
const STOMP_RAISE_S := 0.3
const STOMP_SLAM_S := 0.08
const STOMP_SETTLE_S := 0.32
const STOMP_POSE_S := STOMP_RAISE_S + STOMP_SLAM_S + STOMP_SETTLE_S
const STOMP_COLOR := Color("#ffc447")  # T481: Kanchenjunga's gold (was Etna's orange)
var _stomp_hit_in := -1.0  # server: s until the slam deals the stomp
var slow_s := 0.0
var _stomp_t := 0.0

## Server: arm the stomp -- it lands at the slam (_tick_boosts counts down _stomp_hit_in).
func _stomp() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	_stomp_hit_in = STOMP_RAISE_S + STOMP_SLAM_S

func _stomp_land() -> void:
	if is_dead or health <= 0.0:
		return
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == self or m.get("team") == team or m.get("is_dead") or float(m.get("health")) <= 0.0:
			continue
		var d: float = m.global_position.distance_to(global_position)
		if d > STOMP_R:
			continue
		m.call("take_damage", STOMP_DMG * (1.0 - STOMP_FALLOFF * d / STOMP_R), self)
		if not m.get("is_dead"):
			m.rpc(&"_rpc_boost", "slow", STOMP_SLOW_S)

## Every peer: the leg comes up now; at the slam (_update_legs) a ring races out to the reach and fades.
func _stomp_fx() -> void:
	_stomp_t = STOMP_POSE_S

func _stomp_ring() -> void:
	var host := get_parent()
	if host == null or DisplayServer.get_name() == "headless":
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 48
	tm.ring_segments = 4
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = STOMP_COLOR
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(ring)
	ring.global_position = global_position + Vector3(0, 0.3, 0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(STOMP_R, 1.0, STOMP_R), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)

# ---- T455: Heron FIELD REPAIR (effect_key "field_repair", a duration ability) ----
# User 2026-11-17: "add as many mechs as you think are good" -- nobody supported the team. For the
# ability's 5 s the server repairs Heron and every living ally within FIELD_R (3D distance) by
# FIELD_HPS; health reaches clients in the snapshots (T474). Everyone sees a ring on the ground at the reach (one torus, unshaded, while it runs).
# Calibration knobs.
const FIELD_R := 18.0
const FIELD_HPS := 30.0          # 150 HP over the 5 s
const FIELD_COLOR := Color("#5cff9a")
var field_repair := false
var _field_ring: MeshInstance3D

func _set_field_repair(on: bool) -> void:
	field_repair = on
	_update_field_ring()

# T487 (HUMAN_FOUND 2026-11-18: "Heron should always be able to see its own green circle, allies only
# seeing while it's active is fine."): the pilot of a Heron always sees its reach -- dim while the
# ability is off; everyone else sees the ring only while it runs. Checked every frame (_process).
const FIELD_RING_IDLE_A := 0.35
const FIELD_RING_SEGS := 48
const FIELD_RING_REFIT_M := 0.5
const FIELD_RING_W := 0.35   # m, the ribbon's width
const FIELD_RING_UP := 0.12  # m above the ground
var _ring_fit_at := Vector3(INF, 0, 0)

## T492: the ring's ribbon on the ground round us, FIELD_R out.
func _fit_field_ring() -> void:
	_ring_fit_at = global_position
	var space := get_world_3d().direct_space_state
	var ex: Array = get_exclude_rids()
	var im := _field_ring.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in FIELD_RING_SEGS + 1:
		var a := TAU * float(i) / float(FIELD_RING_SEGS)
		var d := Vector3(cos(a), 0.0, sin(a))
		var y := global_position.y + 0.25
		var top := global_position + d * FIELD_R + Vector3.UP * 8.0
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 24.0)
		q.exclude = ex
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			y = float(hit.position.y) + FIELD_RING_UP
		for r in [FIELD_R - FIELD_RING_W, FIELD_R]:
			var p: Vector3 = global_position + d * r
			im.surface_add_vertex(Vector3(p.x, y, p.z))
	im.surface_end()
var _has_field_repair := false  # configure_abilities

func _update_field_ring() -> void:
	var mine: bool = _has_field_repair and owner_peer_id > 0 and owner_peer_id == multiplayer.get_unique_id() and not is_dead
	if not (field_repair or mine):
		if _field_ring != null:
			_field_ring.visible = false
		return
	if _field_ring == null:
		# T492 (HUMAN_FOUND 2026-11-18: "Heron's beam is not visible into a hill. If it's easy, make it
		# track the ground"): a ribbon draped on the ground (FIELD_RING_SEGS raycasts, refit when the
		# Heron moves FIELD_RING_REFIT_M), not a flat torus at its feet that a slope swallowed. One draw.
		_field_ring = MeshInstance3D.new()
		_field_ring.mesh = ImmediateMesh.new()
		_field_ring.top_level = true  # world space: the ground doesn't turn with the Heron
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = FIELD_COLOR
		_field_ring.material_override = m
		_field_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_field_ring)
		_ring_fit_at = Vector3(INF, 0, 0)
	if global_position.distance_to(_ring_fit_at) > FIELD_RING_REFIT_M:
		_fit_field_ring()
	var c := FIELD_COLOR
	c.a = 1.0 if field_repair else FIELD_RING_IDLE_A
	(_field_ring.material_override as StandardMaterial3D).albedo_color = c
	_field_ring.visible = true

## Server: this tick's repair for every living ally in reach, this mech included.
func _field_repair_tick(delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if health <= 0.0:
		return
	for m in get_tree().get_nodes_in_group("mechs"):
		if m.get("team") == team and m.global_position.distance_to(global_position) <= FIELD_R:
			var got: float = m.call("repair", FIELD_HPS * delta)
			if m != self:
				healed_others_total += got  # T536: XP for healing teammates (not itself)

## Server: add health (not past max, not to the dead); clients see it in the snapshots (T474).
func repair(amount: float) -> float:
	if health <= 0.0 or is_dead or health >= max_health:
		return 0.0
	var before := health
	health = minf(health + amount, max_health)
	return health - before  # T536: what it actually restored

# ---- T430: Denali ANCHOR (ability effect_key "anchor", a duration ability) ----
# Plants its feet for the ability's duration: no walking (it still turns and aims), half damage
# taken, its hits x ANCHOR_DAMAGE_OUT. Server decides; clients learn it from the ability RPCs
# (the owner's prediction stops walking on arrival, reconciled like the jump). Calibration knobs.
# ponytail: a late joiner during the 6 s doesn't see the crouch; add it to the snapshot if that matters.
const ANCHOR_DAMAGE_IN := 0.5
const ANCHOR_DAMAGE_OUT := 1.3
const ANCHOR_CROUCH := 0.6   # leg pose crouch (0..1)
var anchored := false
var _anchor_pose := 0.0

# ---- T473: Taurus CHARGE (ability effect_key "charge") ----
# User 2026-11-18 ("the lunge is just really not what I wanted. Playing around with the Swift made
# me realize that I wanted them separately; dashing skirmisher and lumbering charger"): their original
# 2026-11-08 design with SPACE a toggle instead of held. A press sets it off straight along its facing
# (the aim stays free), speeding up linearly from walking pace to CHARGE_TOP ("High top speed, cap is
# good"); the next press pulls up: the boost bleeds off at CHARGE_DECEL ("quickly, not instant") while
# steering and walking are back at once, so a quick turn and a press keep a little of it (the new
# charge sets off at the speed it still carries along the new heading). No recharge. While it
# charges, an enemy mech (or its front shield) in the way takes RAM_FLOOR..RAM_MAX by charge level (T513)
# and the charge stops dead ("Stop on hit"); a wall met face-on stops it with no damage; it stands
# CHARGE_HIT_S in either impact. Its glow parts and a red aura around the whole body brighten with
# speed. Netcode as the T342 lunge it replaces: the server runs a press on its input tick and tells
# the owner where (_rpc_lunge sets off, _rpc_charge_end pulls up / hits); the owner rewrites the
# ticks it already ran past that record (T205); snapshots carry the clock (lt / ld / lv / le / lh)
# for an RPC that comes late (B131). Other peers run the clock INTERP_DELAY late for pose and glow.
# T513 (user 2026-11-19: "Taurus is too good at getting beacons and not good at brawling." / "Top speed of
# 3.5, ramp it 50% faster than it does now (and get rid of the 15s rule)"): ~1.9 s to the top; a Slip
# (3.75) outruns it. v1 / v2 live at the tags taurus-charge-v1 / -v2.
const CHARGE_TOP := 3.5      # m/s -- calibration knob (Taurus walks 0.9)
const CHARGE_ACCEL := 1.35   # m/s per s from walking pace (v2: 0.9) -- calibration knob
const CHARGE_DECEL := 7.0    # m/s per s once it pulls up: ~0.5 s from the top ("quickly, not instant"; v2: 30 from 15) -- calibration knob
const CHARGE_HIT_S := 0.3    # s it stands in an impact
const CHARGE_CROUCH := 0.35  # leg pose crouch at the top speed: head down, horns first
const CHARGE_AURA_R := 2.2   # m: the aura around the body (its centre CHARGE_AURA_Y up)
const CHARGE_AURA_Y := 1.3
# T499 (user 2026-11-19: "Reenable steering, but make steering decelerate based on how much you turn
# (momentum simulation)" / "90 deg turn means fully killed speed boost ... Goal is to be very strong but
# hard to control"): while it charges it runs along its facing (the aim). Each tick the turn past a
# small free rate costs boost in proportion -- (CHARGE_TOP - walking) per 90 deg, so a 90 deg turn from
# the top, flicked or swept, is back at walking pace -- taken off the curve's set-off speed
# (_charge_v0), so the speed stays a function of the clock and every sync path (rewrites, catch-up,
# pull-up, ram, glow, the snapshot's "lv") carries the loss as it is. The lost speed slides on along
# the old heading (_charge_slip) and bleeds off at CHARGE_SLIP_DECEL: it drifts wide out of a hard
# turn. Server and owner both run it from the same aim inputs.
const CHARGE_TURN_FREE := deg_to_rad(8.0)  # rad/s of turn that costs nothing (aim noise) -- calibration knob
const CHARGE_SLIP_DECEL := 10.0  # m/s per s the slide bleeds off -- calibration knob
var _charge_slip := Vector3.ZERO
# T513 ("Make the damage scale with how long it's been charging, to a pretty high cap, 250?, that takes
# 15s to reach. Glow builds with charge level, not with speed, and is only reduced by turning at 50% the
# rate that the speed is." -- the T499 speed burn is gone, "Remove the self-penalty for now"): a charge
# level 0..1 over CHARGE_LEVEL_S, kept like the speed as an offset on the clock (_charge_l0) so every
# sync path carries it; a turn takes CHARGE_LEVEL_TURN of it per 90 deg (the speed loses all its boost).
# The ram deals RAM_FLOOR..RAM_MAX by level; the glow / aura show the level.
const CHARGE_LEVEL_S := 15.0   # s to a full level -- calibration knob
const CHARGE_LEVEL_TURN := 0.5  # level lost per 90 deg of paid turn -- calibration knob
var _charge_l0 := 0.0
# T517 (user 2026-11-19: "Vertical mouse movement should not change Taurus charge level"): pitch never
# turns the torso, but a quick up / down flick carries some sideways drift -- on a tick the aim moved
# mostly vertically (sideways < CHARGE_VERTICAL_K x the pitch change) that drift is free
const CHARGE_VERTICAL_K := 0.35  # calibration knob
var _charge_pitch_prev := 0.0
const RAM_FLOOR := 60.0      # at a fresh charge -- calibration knob
const RAM_MAX := 250.0       # at a full level -- calibration knob
const LUNGE_GLOW_K := 2.5    # extra glow at full speed (x the palette's energy)
var lunging := false  # the charge / dash clock runs
var bounty := 0  # T364 (server): coins this mech is worth on top of its base -- half of what it killed this life
var lunge_t := 0.0
var _lunge_dir := Vector3.ZERO
var _lunge_glow: Array = []  # [material, base energy] -- this mech's own copies
var _charge := false      # this mech's clock runs the CHARGE curve (configure_abilities)
var _charge_v0 := 0.0     # m/s it set off at
var _charge_end_t := INF  # the clock at the pull-up / impact; INF while it charges
var _aura: MeshInstance3D = null

func charging() -> bool:
	return lunging and _charge and lunge_t < _charge_end_t

func _charge_speed(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < _charge_end_t:
		return minf(CHARGE_TOP, _charge_v0 + CHARGE_ACCEL * t)
	if _lunge_hit:
		return 0.0
	return maxf(0.0, minf(CHARGE_TOP, _charge_v0 + CHARGE_ACCEL * _charge_end_t) - CHARGE_DECEL * (t - _charge_end_t))

## T513: the charge level at clock t (frozen at the pull-up / impact).
func charge_level(t: float) -> float:
	return clampf(_charge_l0 + minf(t, _charge_end_t) / CHARGE_LEVEL_S, 0.0, 1.0)

## T513: the glow -- the level while it charges, fading with the speed through the pull-up.
func _charge_glow(t: float) -> float:
	if t < _charge_end_t:
		return charge_level(t)
	var s_end := _charge_speed(_charge_end_t - 0.0001)
	return 0.0 if _lunge_hit or s_end <= 0.0 else charge_level(t) * _charge_speed(t) / s_end

## This mech's curve at clock t: the dash's or the charge's.
func _curve_speed(t: float) -> float:
	return dash_speed(t) if _dash else _charge_speed(t)

## T473 (server / offline): a press sets the charge off, pulls it up, or -- out of a pull-up -- sets
## it off again from what it still carries along the new heading. Standing in an impact: nothing.
func _charge_press() -> void:
	if lunging and _lunge_hit:
		return
	Game.sync_log_event("ability_on", name, {"slot": -1, "key": "charge"})  # T555 agency (a toggle: on or off)
	if charging():
		_charge_end_t = lunge_t
		_charge_end_rpc(false)
		return
	var dir := _lunge_facing()
	var v0 := maxf(walk_speed, velocity.x * dir.x + velocity.z * dir.z)
	_lunge_begin(dir, 0.0, v0)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_lunge.rpc(input_ack, input_ack_ticks + 1, dir, v0)  # the owner lines up on this tick (T205)

func _charge_end_rpc(hit: bool) -> void:
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_charge_end.rpc(input_ack, input_ack_ticks + 1, _charge_end_t, hit)

# ---- T454: Swift DASH (effect_key "dash", user 2026-11-17: "add as many mechs as you think are
# good"): a short burst along the move input (any direction; the facing if none). It rides the
# lunge's clock, owner prediction (_rpc_lunge) and snapshot sync (_lunge_sync), on its own curve:
# no crouch, no ram damage (a mech or a wall just stops it), no rock-back. Calibration knobs.
const DASH_S := 0.22       # s at speed
const DASH_RAMP_S := 0.04
const DASH_STOP_S := 0.12
const DASH_PEAK := 20.0    # m/s: ~5 m a dash
const DASH_CROUCH := 0.55  # leg pose crouch at mid-dash (0..1)
const DASH_LIFT := 0.12    # m the legs rise at mid-dash (visual): the feet skim
var _dash := false  # this mech's lunge clock runs the DASH curve (configure_abilities)

static func dash_speed(t: float) -> float:
	if t < 0.0:
		return 0.0
	if t < DASH_S:
		var w := 1.0 - minf(t / DASH_RAMP_S, 1.0)
		return DASH_PEAK * (1.0 - w * w)
	var e := t - DASH_S
	if e < DASH_STOP_S:
		var q := 1.0 - e / DASH_STOP_S
		return DASH_PEAK * q * q
	return 0.0

## The curve's phases for this mech: [windup, run, stop, settle] (a charge runs until its end).
func _lphase() -> Array:
	if _dash:
		return [0.0, DASH_S, DASH_STOP_S, 0.0]
	if _lunge_hit:
		return [0.0, _charge_end_t, CHARGE_HIT_S, 0.0]
	return [0.0, _charge_end_t, minf(CHARGE_TOP, _charge_v0 + CHARGE_ACCEL * _charge_end_t) / CHARGE_DECEL, 0.0]

func _ltotal() -> float:
	var p := _lphase()
	return p[0] + p[1] + p[2] + p[3]

func _dash_dir() -> Vector3:
	var d2: Vector2 = _input_source.get_move_direction() if _input_source != null else Vector2.ZERO
	if d2 == Vector2.ZERO:
		return _lunge_facing()
	var aim := torso.global_transform.basis
	var v := aim.x * d2.x + (-aim.z) * -d2.y
	v.y = 0.0
	return v.normalized() if v.length_squared() > 0.0001 else _lunge_facing()

func _lunge_facing() -> Vector3:
	var f := -torso.global_transform.basis.z
	f.y = 0.0
	return f.normalized() if f.length_squared() > 0.0001 else Vector3.FORWARD

var _lunge_hit := false  # T404: a ram / wall: stands in place
var _lunge_hit_t := 0.0   # T404: the clock at that impact (the owner's sync compares with it)

var _lunge_begin_ms := -100000  # T454: when this peer last started a charge / dash

func _lunge_begin(dir: Vector3, t0 := 0.0, v0 := 0.0) -> void:
	_lunge_begin_ms = Time.get_ticks_msec()
	lunging = true
	lunge_t = t0
	_lunge_dir = dir
	_lunge_hit = false
	_charge_v0 = v0
	_charge_end_t = INF
	_charge_slip = Vector3.ZERO
	_charge_l0 = 0.0  # T513: every set-off builds from nothing
	_charge_pitch_prev = _camera_pitch  # T517

func _lunge_end() -> void:
	lunging = false
	_set_lunge_glow(0.0)

## Server + owner: advance the curve one tick and drive the horizontal velocity; false = not running.
func _lunge_step(delta: float) -> bool:
	if not lunging:
		return false
	lunge_t += delta
	if lunge_t >= _ltotal():
		_lunge_end()
		return false
	if _charge and not _lunge_hit and lunge_t < _charge_end_t:
		_charge_steer(delta)  # T499
	var sp := 0.0 if _lunge_hit else _curve_speed(lunge_t)
	velocity.x = _lunge_dir.x * sp
	velocity.z = _lunge_dir.z * sp
	if _charge and _charge_slip != Vector3.ZERO:  # T499: the slide out of a turn
		_charge_slip = _charge_slip.move_toward(Vector3.ZERO, CHARGE_SLIP_DECEL * delta)
		velocity.x += _charge_slip.x
		velocity.z += _charge_slip.z
	if _charge and not _lunge_hit and lunge_t >= _charge_end_t:
		# T473: pulled up -- it steers and walks again while the boost bleeds off
		var d2: Vector2 = _input_source.get_move_direction() if _input_source != null else Vector2.ZERO
		_desired_move_dir = Vector3.ZERO
		if d2 != Vector2.ZERO:
			var aim := torso.global_transform.basis
			_desired_move_dir = (aim.x * d2.x + (-aim.z) * -d2.y).normalized()
			velocity.x += _desired_move_dir.x * walk_speed
			velocity.z += _desired_move_dir.z * walk_speed
	_set_lunge_glow(sp / DASH_PEAK if _dash else _charge_glow(lunge_t))  # T513
	return true

## T499: the heading follows the facing; a turn past the free rate costs boost (off the set-off speed,
## so the clock curve carries it) and the lost speed slides on along the old heading; T513: and level.
func _charge_steer(delta: float) -> void:
	var h := _lunge_facing()
	var yaw := absf(_lunge_dir.signed_angle_to(h, Vector3.UP))
	var dpitch := absf(_camera_pitch - _charge_pitch_prev)
	_charge_pitch_prev = _camera_pitch
	if yaw < CHARGE_VERTICAL_K * dpitch:
		yaw = 0.0  # T517: a vertical mouse move's drift
	var paid := maxf(0.0, yaw - CHARGE_TURN_FREE * delta)
	var s := _charge_speed(lunge_t)
	if paid > 0.0:
		var lost := minf(maxf(0.0, s - walk_speed), (CHARGE_TOP - walk_speed) * paid / (PI * 0.5))
		if lost > 0.0:
			_charge_slip += _lunge_dir * lost
			_charge_v0 = s - lost - CHARGE_ACCEL * lunge_t
		var lv := charge_level(lunge_t)  # T513: the level pays half the rate
		_charge_l0 = maxf(0.0, lv - CHARGE_LEVEL_TURN * paid / (PI * 0.5)) - lunge_t / CHARGE_LEVEL_S
	_lunge_dir = h

## Other peers: the clock for the pose and glow only.
func _lunge_visual_tick(delta: float) -> void:
	if not lunging:
		return
	lunge_t += delta
	if lunge_t >= _ltotal():
		_lunge_end()
	else:
		_set_lunge_glow(_curve_speed(lunge_t) / DASH_PEAK if _dash else _charge_glow(lunge_t))  # T513

## After each move: a mech (or its shield) or a wall in the way ends the run; the server deals the
## ram. The owner's prediction stops the same way at walls; a mech is the server's call.
func _lunge_contacts() -> void:
	var ph := _lphase()
	if not lunging or _lunge_hit or lunge_t < ph[0] or lunge_t >= ph[0] + ph[1]:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var c := col.get_collider() as Node
		var m := _owning_mech(c)
		if m != null and m != self:
			var server := not multiplayer.has_multiplayer_peer() or multiplayer.is_server()
			if not server:
				# T404: the owner's prediction meets other mechs where they were INTERP_DELAY ago; a ram
				# is the server's call -- its _rpc_charge_end (or the snapshot's clock) tells us
				continue
			if m.get("team") != team and c.has_method("take_damage") and not _dash:  # T454: a dash doesn't ram
				c.call("take_damage", lerpf(RAM_FLOOR, RAM_MAX, charge_level(lunge_t)), self)  # T513: by level
			_lunge_impact()
			return
		if col.get_normal().dot(-_lunge_dir) > 0.6 and _step_up_remaining <= 0.0:  # a step lifts it instead
			_lunge_impact()
			return

## Hit something: a dash skips to its end; a charge stands CHARGE_HIT_S where it is (T473).
func _lunge_impact() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	_charge_slip = Vector3.ZERO  # T499: stops dead
	_lunge_hit = true
	_lunge_hit_t = lunge_t
	if _charge:
		_charge_end_t = lunge_t
		_charge_end_rpc(true)
		return
	var ph := _lphase()
	lunge_t = ph[0] + ph[1] + ph[2]

func _lunge_stop() -> void:
	_lunge_end()
	velocity.x = 0.0
	velocity.z = 0.0

## Owner: the record for tick n on input seq in the prediction history; -1 if gone.
func _hist_index(seq: int, n: int) -> int:
	for k in range(_pred_hist.size() - 1, -1, -1):
		var h: Array = _pred_hist[k]
		if int(h[0]) == seq and int(h[1]) <= n:
			return k
		if int(h[0]) < seq:
			break
	return -1

## Owner: the records after idx (and us) get the motion the curve gives from there; lunge_t is the
## clock at idx on the way in, ours now on the way out.
func _lunge_rewrite(idx: int) -> void:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var base: Vector3 = _pred_hist[idx][2]
	var off := Vector3.ZERO
	for k in range(idx + 1, _pred_hist.size()):
		lunge_t += dt
		off += _lunge_dir * _curve_speed(lunge_t) * dt
		var rec: Vector3 = _pred_hist[k][2]
		_pred_hist[k][2] = Vector3(base.x + off.x, rec.y, base.z + off.z)
	if idx + 1 < _pred_hist.size():
		global_position = Vector3(base.x + off.x, global_position.y, base.z + off.z)

## Owner: the server started the run after its tick (seq, n). Ticks this client already ran past
## that record get the motion they missed (horizontal), records included, so the next snapshots
## compare like with like. Not in the history -> start now; reconcile eases the rest.
@rpc("authority", "reliable")
func _rpc_lunge(seq: int, n: int, dir: Vector3, v0: float) -> void:
	if not _predicting():
		_lunge_begin(dir, -INTERP_DELAY, v0)
		return
	if Time.get_ticks_msec() - _lunge_snap_start_ms < LUNGE_RPC_STALE_MS:
		return  # T454: a snapshot already started this one (_lunge_sync); a second start ran it twice
	var idx := _hist_index(seq, n)
	_lunge_begin(dir, 0.0, v0)
	if idx >= 0:
		_lunge_rewrite(idx)

## T473: the server's charge pulled up (hit = an impact) after its tick (seq, n), clock t_end. The
## owner rewrites the ticks it ran past that record as for the start; others' clocks, INTERP_DELAY
## late, reach t_end in step with the motion they're shown.
@rpc("authority", "reliable")
func _rpc_charge_end(seq: int, n: int, t_end: float, hit: bool) -> void:
	if not lunging or not _charge:
		return  # over here already (our own impact's stand ran out; a snapshot) -- or never started
	_charge_end_t = t_end
	_lunge_hit = hit
	_lunge_hit_t = t_end
	if not _predicting():
		return
	var idx := _hist_index(seq, n)
	if idx >= 0:
		lunge_t = t_end
		_lunge_rewrite(idx)

## B131 (lunge_net@bad: 3 snaps in one dash): on a lossy link the reliable _rpc_lunge can land
## after later snapshots -- and reconcile has trimmed the history record it needs by then -- so the
## owner started its run late. Each snapshot of our mech carries the server's clock ("lt", at the
## record it acks): start from it if we missed the start, keep our clock on it, and stop when the
## server's run stopped (a ram) before ours. `ahead` = our records after that one.
func _lunge_sync(entry: Dictionary, ahead: int) -> void:
	if _charge:
		_charge_sync(entry, ahead)
		return
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var slt: float = float(entry.get("lt", -1.0))
	if slt >= 0.0:
		var want := slt + float(ahead) * dt
		if want >= _ltotal():
			return
		if not lunging:
			var missed := Time.get_ticks_msec() - _lunge_begin_ms > int((_ltotal() + 0.5) * 1000.0)
			_lunge_begin(entry.get("ld", _lunge_facing()), want)
			if missed:  # T454: we never started this one (its start RPC is late or lost)
				_lunge_catch_up(slt, ahead)
				_lunge_snap_start_ms = Time.get_ticks_msec()
		else:
			# T404 (B147): we run ~a round trip ahead, so we meet a wall before the server's copy does;
			# ours stands until the server's own clock passes our impact still running (it met nothing
			# there: ours was local); its clock jumping to the end while we run -> stop too.
			var ph := _lphase()
			var settle0: float = ph[0] + ph[1] + ph[2]
			if _lunge_hit:
				if slt < settle0 and slt > _lunge_hit_t + 2.0 * dt:
					_lunge_hit = false
					lunge_t = want
				elif want > lunge_t + 1.5 * dt:
					lunge_t = want  # forward only: a stopped run never goes back into it
				return
			if want >= settle0 and lunge_t < settle0 - 2.0 * dt:
				_lunge_hit = true
			if absf(lunge_t - want) > 1.5 * dt:
				lunge_t = want
	elif lunging and lunge_t > float(ahead + 1) * dt:  # ours began before that record; the server's is over
		_lunge_stop()

## T473: the charge's side of _lunge_sync. The snapshot also carries the server's set-off speed
## (lv), its end clock (le, -1 while it charges) and whether that end was an impact (lh).
func _charge_sync(entry: Dictionary, ahead: int) -> void:
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var slt: float = float(entry.get("lt", -1.0))
	if slt < 0.0:
		if lunging and lunge_t > float(ahead + 1) * dt:  # ours began before that record; the server's is over
			_lunge_stop()
		return
	var want := slt + float(ahead) * dt
	var se: float = float(entry.get("le", -1.0))
	var sh: bool = bool(entry.get("lh", false))
	var sv: float = float(entry.get("lv", walk_speed))
	var sd: Vector3 = entry.get("ld", _lunge_facing())
	if not lunging:
		var send := INF
		if se >= 0.0:
			send = se + (CHARGE_HIT_S if sh else minf(CHARGE_TOP, sv + CHARGE_ACCEL * se) / CHARGE_DECEL)
		if want >= send:
			return  # the server's is over by now too
		if _lunge_hit and slt <= _lunge_hit_t + 2.0 * dt and sd.dot(_lunge_dir) > 0.999:
			return  # B147: ours stood in an impact the server's copy hadn't reached in that snapshot
		var missed := Time.get_ticks_msec() - _lunge_begin_ms > int((want + 0.5) * 1000.0)
		_lunge_begin(sd, want, sv)
		_charge_l0 = float(entry.get("ll", 0.0))  # T513
		_charge_end_t = se if se >= 0.0 else INF
		_lunge_hit = sh and se >= 0.0
		_lunge_hit_t = se
		if missed:  # we never started this one (its start RPC is late or lost)
			_lunge_catch_up(slt, ahead)
			_lunge_snap_start_ms = Time.get_ticks_msec()
		return
	if se < 0.0 and not is_inf(_charge_end_t) and not _lunge_hit and absf(lunge_t - want) > 6.0 * dt:
		# a new charge the server set off out of our pull-up (its _rpc_lunge is late): take it up
		_lunge_begin(sd, want, sv)
		_charge_l0 = float(entry.get("ll", 0.0))  # T513
		_lunge_snap_start_ms = Time.get_ticks_msec()
		return
	if se >= 0.0 and is_inf(_charge_end_t):
		# the server's pull-up / ram we haven't had (its _rpc_charge_end is late): end there too
		_charge_end_t = se
		_lunge_hit = sh
		_lunge_hit_t = se
		if absf(lunge_t - want) > 1.5 * dt:
			lunge_t = want
		return
	if _lunge_hit and se < 0.0:
		# B147: ours hit a wall the server's copy hadn't reached in that snapshot -- stand; once the
		# server's own clock passes our impact still charging, ours was local: charge on
		if slt > _lunge_hit_t + 2.0 * dt:
			_lunge_hit = false
			_charge_end_t = INF
			lunge_t = want
		return
	if not is_inf(_charge_end_t):
		return  # ours ended on the server's word; a snapshot from before it changes nothing
	if absf(lunge_t - want) > 1.5 * dt:
		lunge_t = want

## T454 (dash_net@bad: 5 snaps / 3 dashes): a run we never started (its start RPC late or lost;
## not one of ours that already ended early -- lunge_net: that moved Taurus 8 m) left us standing
## where the server's copy had already moved off -> a snap. Move the matched record, the ones after
## it, and us by the distance the server's copy covered by each one's clock (slt at the matched
## record, a tick more per record), as _rpc_lunge does.
const LUNGE_RPC_STALE_MS := 1500  # over any RPC delay, under the dash's recharge
var _lunge_snap_start_ms := -100000

func _lunge_catch_up(slt: float, ahead: int) -> void:
	var i := _pred_hist.size() - 1 - ahead
	if i < 0:
		return
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	var dist := 0.0
	var t := 0.0
	while t + dt <= slt + 0.5 * dt:
		t += dt
		dist += _curve_speed(t) * dt
	for k in range(i, _pred_hist.size()):
		if k > i:
			t += dt
			dist += _curve_speed(t) * dt
		var rec: Vector3 = _pred_hist[k][2]
		_pred_hist[k][2] = Vector3(rec.x + _lunge_dir.x * dist, rec.y, rec.z + _lunge_dir.z * dist)
	global_position += Vector3(_lunge_dir.x * dist, 0.0, _lunge_dir.z * dist)

## Leg pose for BipedLegs: (crouch 0..1, leap 0..1, lift m).
func lunge_pose() -> Vector3:
	if not lunging or lunge_t < 0.0:
		return Vector3.ZERO
	if _dash:  # T454: a braced crouch and a slight thruster lift, in and out over the dash, no leap
		var k := sin(PI * clampf(lunge_t / (DASH_S + DASH_STOP_S), 0.0, 1.0))
		return Vector3(DASH_CROUCH * k, 0.0, DASH_LIFT * k)
	# T473: head down, horns first, deeper with speed; the legs run under it (BipedLegs caps the cadence)
	return Vector3(CHARGE_CROUCH * clampf(_charge_speed(lunge_t) / CHARGE_TOP, 0.0, 1.0), 0.0, 0.0)

## Glow parts brighten with speed: this mech's own copies of its (shared, T310) glow materials.
## T473 (user: "Make the Taurus exude a red glow all around that gets brighter as it accelerates"):
## a charger also wears an additive aura (one draw while it shows, none otherwise).
func _set_lunge_glow(k: float) -> void:
	if _charge and (_aura != null or k > 0.0):
		_charge_aura(k)
	if _lunge_glow.is_empty():
		if k <= 0.0:
			return
		for mi in find_children("*", "MeshInstance3D", true, false):
			var n := mi as MeshInstance3D
			if n.mesh == null or n.mesh.get_surface_count() == 0:  # B75 / B111: no surface, no override
				continue
			for s in n.mesh.get_surface_count():  # T528: the skinned kit body carries every material as a surface
				var mat := n.get_surface_override_material(s) as StandardMaterial3D
				if mat != null and mat.emission_enabled and n.get_parent() != null and not n.get_parent().name.begins_with("Hardpoint"):
					var own := mat.duplicate() as StandardMaterial3D
					n.set_surface_override_material(s, own)
					_lunge_glow.append([own, own.emission_energy_multiplier])
	for g in _lunge_glow:
		(g[0] as StandardMaterial3D).emission_energy_multiplier = float(g[1]) * (1.0 + LUNGE_GLOW_K * k)

func _charge_aura(k: float) -> void:
	if _aura == null:
		if DisplayServer.get_name() == "headless":
			return
		var sm := SphereMesh.new()
		sm.radius = CHARGE_AURA_R
		sm.height = CHARGE_AURA_R * 2.0
		sm.radial_segments = 24
		sm.rings = 12
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/charge_aura.gdshader")
		sm.material = mat  # on the mesh: nothing else overrides it
		_aura = MeshInstance3D.new()
		_aura.name = "ChargeAura"
		_aura.mesh = sm
		_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aura.position = Vector3(0.0, CHARGE_AURA_Y, 0.0)
		add_child(_aura)
	_aura.visible = k > 0.02
	(_aura.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("k", clampf(k, 0.0, 1.0))

func _jump_launch() -> void:
	velocity.y = 15.0
	# T240 (HUMAN_FOUND_ISSUES 2026-11-04): standing still, the jump goes straight up (it
	# lunged along the facing); moving, it carries the move direction as before
	velocity.x = _desired_move_dir.x * walk_speed * 3.75
	velocity.z = _desired_move_dir.z * walk_speed * 3.75

@rpc("authority", "reliable")
func _rpc_ability_activated(slot: int) -> void:
	if slot < 0 or slot >= _abilities.size():
		return
	Game.sync_log_event("ability_seen", name, {"slot": slot})  # T555 parity
	var ability: Resource = _abilities[slot]
	if ability.duration > 0.0:  # T468: the HUD's copies
		_ability_active_timers[ability.effect_key] = ability.duration
	else:
		_ability_cooldowns[ability.effect_key] = _spend_charge(ability, ability_cooldown(ability))  # T454 charges too
	match ability.effect_key:
		"jump_heal":
			if _predicting():
				_jump_launch()  # T205: the owner's prediction flies too (one RTT/2 late)
		"stealth":
			is_stealthy = true
			_apply_stealth_visual(true)
		"anchor":
			anchored = true  # the owner's prediction stops too (one RTT/2 late, reconciled)
		"field_repair":
			_set_field_repair(true)  # T455: the ring, for everyone
		"stomp":
			_stomp_fx()  # T456: the shockwave and the crouch; the damage and slow are the server's

@rpc("authority", "reliable")
func _rpc_ability_deactivated(slot: int) -> void:
	if slot < 0 or slot >= _abilities.size():
		return
	var ability: Resource = _abilities[slot]
	_ability_active_timers[ability.effect_key] = 0.0  # T468: the HUD's copies
	_ability_cooldowns[ability.effect_key] = ability_cooldown(ability)
	match ability.effect_key:
		"stealth":
			is_stealthy = false
			_apply_stealth_visual(false)
		"field_repair":
			_set_field_repair(false)
		"anchor":
			anchored = false
