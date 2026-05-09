class_name AIInputSource
extends "res://scripts/InputSource.gd"

const TURN_SPEED    := 1.8   # rad/s
const ENGAGE_DIST   := 35.0  # close enough to shoot
const RETREAT_DIST  := 8.0   # too close - back off
const AIM_THRESHOLD := 0.25  # fire when within this many radians of target
const BURST_FIRE    := 1.6   # seconds of continuous fire per burst
const BURST_PAUSE   := 0.85  # seconds of pause between bursts
const STUCK_CHECK     := 0.5   # seconds between stuck checks
const STUCK_DIST      := 0.5   # minimum movement to not be considered stuck (m)
const ESCAPE_TIME     := 1.2   # base seconds to escape when stuck
const ESCAPE_TIME_MAX := 4.0   # maximum escape time for repeatedly stuck bots
const AVOID_ZONE_TIME := 40.0  # seconds to avoid the stuck zone
const AVOID_RADIUS    := 18.0  # radius (m) around stuck position to avoid beacons
const LOS_INTERVAL  := 0.12  # seconds between line-of-sight raycasts

# [aim_jitter_radians, turn_speed_scale]
const DIFFICULTY_PRESETS: Array = [
	{"aim_jitter": 0.18,  "turn_scale": 0.55},  # Easy
	{"aim_jitter": 0.055, "turn_scale": 1.00},  # Normal
	{"aim_jitter": 0.015, "turn_scale": 1.50},  # Medium
	{"aim_jitter": 0.005, "turn_scale": 1.85},  # Hard
	{"aim_jitter": 0.0,   "turn_scale": 2.20},  # Elite
]

# Role: "attacker" pushes enemy beacons, "defender" guards own beacons,
# "flanker" prioritises neutral beacons and approaches from the side.
# Assigned randomly at spawn with a sensible distribution (2:1:1 ratio).
var role: String = "attacker"

var _target: Node3D = null
var _enemy_mechs: Array = []   # all enemy mechs found at spawn time
var _beacons: Array = []
var _own_team: int = 1
var _claimed_beacon: Node = null   # beacon we told AIDirector we're heading to
var _look_delta: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.ZERO
var _firing: bool = false
var _strafe_timer: float = 0.0
var _strafe_sign: float = 1.0
var _burst_timer: float = BURST_FIRE
var _in_burst: bool = true
var _jitter: Vector2 = Vector2.ZERO
var _jitter_timer: float = 0.0
var _last_pos: Vector3 = Vector3.ZERO
var _stuck_timer: float = STUCK_CHECK
var _stuck_count: int = 0
var _escape_timer: float = 0.0
var _escape_vec: Vector2 = Vector2.RIGHT
var _avoid_zone:  Vector3 = Vector3(INF, 0.0, INF)  # stuck position to route around
var _avoid_timer: float = 0.0
var _target_refresh: float = 0.0
var _has_clear_shot: bool = false
var _los_timer: float = 0.0

func _ready() -> void:
	call_deferred("_find_targets")

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		AIDirector.clear_intent(get_parent())

func _find_targets() -> void:
	_own_team = get_parent().get("team") if get_parent() != null else 1
	for mech in get_tree().get_nodes_in_group("mechs"):
		if mech.get("team") != _own_team:
			_enemy_mechs.append(mech)
	_beacons = get_tree().get_nodes_in_group("beacons")
	# Randomly assign a role with a 2:1:1 split among bots on the same team.
	var r := randf()
	if r < 0.50:
		role = "attacker"
	elif r < 0.75:
		role = "defender"
	else:
		role = "flanker"

func _pick_closest_enemy(from: Node3D) -> Node3D:
	var best: Node3D = null
	var best_dist := INF
	for em in _enemy_mechs:
		if not is_instance_valid(em) or not em.visible:
			continue
		if em.get("is_stealthy"):
			continue
		var d: float = from.global_position.distance_to(em.global_position)
		if d < best_dist:
			best_dist = d
			best = em
	return best

# Picks the best target by blending distance and target health.
# Prefers enemies that are already damaged (focus-fire) without completely
# ignoring closer threats.
func _pick_best_target(from: Node3D) -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	for em in _enemy_mechs:
		if not is_instance_valid(em) or not em.visible:
			continue
		if em.get("is_stealthy"):
			continue
		var d: float = from.global_position.distance_to(em.global_position)
		var max_hp: float = maxf(em.get("max_health") if em.get("max_health") != null else 1.0, 1.0)
		var hp_pct: float = clampf(em.health / max_hp, 0.0, 1.0)
		# High score = close + low HP.  HP weight 12 vs distance weight 0.1.
		var score := (1.0 - hp_pct) * 12.0 - d * 0.1
		if score > best_score:
			best_score = score
			best = em
	return best

func _pick_target_beacon(bot_mech: Node3D) -> Node:
	var best: Node = null
	var best_score := -INF
	for b in _beacons:
		if not is_instance_valid(b):
			continue
		# Skip beacons in the stuck zone.
		if _avoid_timer > 0.0 and \
				Vector2(b.global_position.x - _avoid_zone.x, b.global_position.z - _avoid_zone.z).length() < AVOID_RADIUS:
			continue
		var owner: int = b.get("owner_team") if b.get("owner_team") != null else -1
		var dist: float = bot_mech.global_position.distance_to(b.global_position)
		var priority: float
		match role:
			"defender":
				if owner == 1:
					priority = 15.0
				elif owner == -1:
					priority = 3.0
				else:
					priority = 1.0
			"flanker":
				if owner == -1:
					priority = 14.0
				elif owner == 0:
					priority = 6.0
				else:
					continue
			_: # "attacker"
				if owner == 1:
					continue
				priority = 10.0 if owner == -1 else 5.0
		var already: int = AIDirector.intent_count(b, _own_team)
		var crowd_penalty: float = maxf(0.0, float(already - 1)) * 5.0
		var score: float = priority - dist * 0.05 - crowd_penalty
		if score > best_score:
			best_score = score
			best = b
	return best

# Register or update our beacon intent with the AIDirector.
func _claim_beacon(beacon: Node) -> void:
	if beacon == _claimed_beacon:
		return
	_claimed_beacon = beacon
	if beacon != null:
		AIDirector.set_intent(get_parent(), beacon, _own_team)
	else:
		AIDirector.clear_intent(get_parent())

# Returns true when no collideable geometry lies between the bot's eye and the
# target's centre.  Uses the same PhysicsRayQueryParameters3D pattern as the
# weapon scripts so it respects the same collision layers.
func _check_los(bot_mech: Node3D) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.visible:
		_has_clear_shot = false
		return
	var eye: Vector3 = bot_mech.global_position + Vector3(0, 2.0, 0)
	var tgt: Vector3 = _target.global_position + Vector3(0, 1.5, 0)
	var space := bot_mech.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye, tgt)
	query.exclude = bot_mech.get_exclude_rids()
	var result := space.intersect_ray(query)
	# Clear shot if nothing blocked, or if what we hit IS the target body.
	_has_clear_shot = result.is_empty() or result.get("collider") == _target

# Returns the immediate nav-path waypoint toward goal_pos, or Vector3.ZERO if
# the navmesh is not ready yet (caller falls back to direct steering).
func _nav_next(bot_mech: Node3D, goal_pos: Vector3) -> Vector3:
	var nav_agent := bot_mech.get_node_or_null("NavAgent") as NavigationAgent3D
	if nav_agent == null:
		return Vector3.ZERO
	nav_agent.target_position = goal_pos
	var next := nav_agent.get_next_path_position()
	# When no path exists yet (navmesh not baked or no route found),
	# get_next_path_position() returns the agent's current position.
	# Treat that as "not ready" and fall back to direct steering.
	if bot_mech.global_position.distance_to(next) < 1.0:
		return Vector3.ZERO
	return next

func _process(delta: float) -> void:
	var bot_mech: Node3D = get_parent().get("pawn")
	if bot_mech == null:
		_look_delta = Vector2.ZERO
		_move_dir   = Vector2.ZERO
		_firing     = false
		return

	# Refresh target periodically or when current target is no longer valid.
	_target_refresh -= delta
	if _target_refresh <= 0.0 or not is_instance_valid(_target) or not _target.visible:
		_target_refresh = 0.5
		_target = _pick_best_target(bot_mech)

	# Periodically check line-of-sight to target.
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = LOS_INTERVAL
		_check_los(bot_mech)

	var has_target: bool = _target != null and is_instance_valid(_target) and _target.visible and not _target.get("is_stealthy")
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
	var diff_idx: int = clampi(Game.settings.get("bot_difficulty", 1), 0, 4)
	var preset: Dictionary = DIFFICULTY_PRESETS[diff_idx]
	var aim_jitter: float = preset.get("aim_jitter", 0.055)
	var eff_turn: float = TURN_SPEED * preset.get("turn_scale", 1.0)

	var angle_h := 0.0
	var dist := INF

	if has_target:
		var to_target := _target.global_position - bot_mech.global_position
		dist = to_target.length()

		# Horizontal aim
		var to_flat := Vector3(to_target.x, 0.0, to_target.z)
		var h_dist  := to_flat.length()
		if h_dist > 0.01:
			to_flat = to_flat / h_dist
			angle_h = (-bot_mech.get_aim_basis().z).signed_angle_to(to_flat, Vector3.UP)
		angle_h += _jitter.x
		var turn_h: float = clamp(angle_h, -eff_turn * delta, eff_turn * delta)
		_look_delta.x = -turn_h / sens

		# Vertical aim
		var cam_arm := bot_mech.get_node_or_null("Torso/CameraArm") as SpringArm3D
		var cam     := bot_mech.get_node_or_null("Torso/CameraArm/Camera3D") as Camera3D
		if cam_arm and cam:
			var target_centre := _target.global_position + Vector3(0, 1.0, 0)
			var cam_to_target := target_centre - cam.global_position
			var cam_h_dist: float = Vector2(cam_to_target.x, cam_to_target.z).length()
			var desired_pitch: float = atan2(cam_to_target.y, maxf(cam_h_dist, 0.01))
			var pitch_diff: float    = desired_pitch - cam_arm.rotation.x + _jitter.y
			var turn_v: float        = clamp(pitch_diff, -eff_turn * delta, eff_turn * delta)
			_look_delta.y = -turn_v / sens
	else:
		_look_delta = Vector2.ZERO
		_firing = false

	# Movement - retreat takes priority; otherwise navigate to beacon/enemy.
	var own_max_hp: float = maxf(bot_mech.get("max_health") if bot_mech.get("max_health") != null else 1.0, 1.0)
	var own_hp_pct: float = clampf(bot_mech.health / own_max_hp, 0.0, 1.0)
	var role_retreat_dist := RETREAT_DIST * (1.5 if role == "defender" else 1.0)
	if own_hp_pct < 0.20 and has_target:
		var away := (bot_mech.global_position - _target.global_position)
		away.y = 0.0
		if away.length_squared() > 0.01:
			away = away.normalized()
			var aim_basis: Basis = bot_mech.call("get_aim_basis")
			_move_dir = Vector2(away.dot(aim_basis.x), -away.dot(-aim_basis.z)).normalized()
		_firing = false
	elif has_target and dist < role_retreat_dist:
		_move_dir = Vector2(0.0, 1.0)
		_claim_beacon(null)
	else:
		var beacon := _pick_target_beacon(bot_mech)
		_claim_beacon(beacon)
		var goal_pos: Vector3 = Vector3.ZERO
		if beacon != null:
			goal_pos = beacon.global_position
		elif has_target:
			goal_pos = _target.global_position

		if goal_pos != Vector3.ZERO:
			var aim_basis: Basis = bot_mech.call("get_aim_basis")
			var fwd:   Vector3 = -aim_basis.z
			var right: Vector3 = aim_basis.x
			# Try nav-agent path first; fall back to direct steering if not ready.
			var next := _nav_next(bot_mech, goal_pos)
			var steer: Vector3
			if next != Vector3.ZERO:
				steer = next - bot_mech.global_position
			else:
				steer = goal_pos - bot_mech.global_position
			steer.y = 0.0
			var sd := steer.length()
			if sd > 1.5:
				steer = steer / sd
				_move_dir = Vector2(steer.dot(right), -steer.dot(fwd)).normalized()
			else:
				_move_dir = Vector2.ZERO
		elif has_target:
			# All beacons owned - circle-strafe and fight.
			_strafe_timer -= delta
			if _strafe_timer <= 0.0:
				_strafe_timer = randf_range(1.5, 3.0)
				_strafe_sign  = 1.0 if randf() > 0.5 else -1.0
			if dist > ENGAGE_DIST:
				_move_dir = Vector2(0.0, -1.0)
			else:
				_move_dir = Vector2(_strafe_sign, -0.3).normalized()
		else:
			_move_dir = Vector2.ZERO

	# Decay stuck-zone avoidance cooldown.
	if _avoid_timer > 0.0:
		_avoid_timer -= delta
		if _avoid_timer <= 0.0:
			_avoid_zone = Vector3(INF, 0.0, INF)

	# Stuck detection - if not making progress while moving, escape.
	# Tracks consecutive stuck events to escalate escape aggressiveness.
	_stuck_timer -= delta
	if _stuck_timer <= 0.0:
		_stuck_timer = STUCK_CHECK
		if _move_dir != Vector2.ZERO and \
				bot_mech.global_position.distance_to(_last_pos) < STUCK_DIST:
			_stuck_count += 1
			_escape_timer = minf(ESCAPE_TIME * _stuck_count, ESCAPE_TIME_MAX)
			var side := 1.0 if randf() > 0.5 else -1.0
			if _stuck_count <= 1:
				# First escape: sideways strafe
				_escape_vec = Vector2(side, -0.3).normalized()
			elif _stuck_count <= 2:
				# Second escape: back up with a sideways component
				_escape_vec = Vector2(side * 0.4, 0.9).normalized()
			else:
				# Repeated stuck: fully random direction to break the oscillation
				var angle := randf_range(0.0, TAU)
				_escape_vec = Vector2(cos(angle), sin(angle))
				# Mark the entire area as a stuck zone so ALL nearby beacons are avoided
				_avoid_zone  = bot_mech.global_position
				_avoid_timer = AVOID_ZONE_TIME
				_claim_beacon(null)
			# Reset so we don't immediately re-trigger stuck detection
			_last_pos = bot_mech.global_position
		else:
			_stuck_count = maxi(0, _stuck_count - 1)
			_last_pos = bot_mech.global_position

	if _escape_timer > 0.0:
		_escape_timer -= delta
		_move_dir = _escape_vec

	if has_target:
		# Aim jitter - slow random drift that makes the bot miss occasionally
		_jitter_timer -= delta
		if _jitter_timer <= 0.0:
			_jitter_timer = randf_range(0.08, 0.18)
			_jitter = Vector2(randf_range(-aim_jitter, aim_jitter),
							  randf_range(-aim_jitter, aim_jitter))
		# Burst fire - shoot for BURST_FIRE seconds, pause for BURST_PAUSE seconds
		_burst_timer -= delta
		if _burst_timer <= 0.0:
			_in_burst = not _in_burst
			_burst_timer = BURST_FIRE if _in_burst else BURST_PAUSE

		# Fire when aimed closely enough, in range, in burst window, and LOS is clear.
		_firing = _in_burst and abs(angle_h) < AIM_THRESHOLD and dist < ENGAGE_DIST + 15.0 and _has_clear_shot

func get_move_direction() -> Vector2:
	return _move_dir

func get_look_delta() -> Vector2:
	return _look_delta

func is_firing_primary() -> bool:
	return _firing
