class_name AIInputSource
extends "res://scripts/InputSource.gd"

const TURN_SPEED    := 0.9   # rad/s
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
const THREAT_MEMORY := 4.0   # T169: seconds an attacker stays a priority target
const THREAT_BONUS  := 8.0   # T169: score bonus for the recent attacker (~ 2/3 of a dying target)
const RETALIATE_CD  := 3.0   # T169: min seconds between damage-driven switches (no ping-pong)
const FINISH_HP     := 0.25  # T169: keep the current target below this HP fraction
const HELP_RADIUS   := 60.0  # T172: teammates this close hear who is shooting us
const FOCUS_BONUS   := 5.0   # T172: score per teammate already on that target (max 3)
const VISIBLE_BONUS := 6.0   # T172: candidate in line of sight
const CLOSE_RANGE   := 15.0  # T190: an enemy inside this takes priority over the focus target
const CLOSE_BONUS   := 40.0  # T190: tapers to 0 at CLOSE_RANGE; inside ~10 m beats focus + sight
const OUTNUMBER_RADIUS := 30.0  # T189: friends vs foes this close decide push or fall back
const CLAIM_STICKY := 3.0       # T189: score bonus for the beacon we already head for
const CHASE_DIST    := 80.0  # T172: follow a target that broke line of sight

# T172. aim_jitter = radians of slow aim drift; turn_scale x TURN_SPEED = max turn rate;
# lead = fraction of the target's motion aimed ahead (projectile flight time);
# reaction = seconds before the first shot at a new target; pause = BURST_PAUSE scale
# (0 = hold the trigger); tactics = fight movement (keep weapon range + strafe), fire
# only on a hit-worthy aim / full charge / lock, abilities, chase, reload in lulls;
# team = focus fire, help calls, attackers share one objective beacon + regroup;
# juke = reverse the strafe the moment we're hit (beats an opponent leading the shot).
const DIFFICULTY_PRESETS: Array = [
	{"aim_jitter": 0.18,  "turn_scale": 0.55, "lead": 0.0, "reaction": 0.70, "pause": 1.0,  "tactics": false, "team": false},  # Easy
	{"aim_jitter": 0.055, "turn_scale": 1.00, "lead": 0.5, "reaction": 0.45, "pause": 1.0,  "tactics": false, "team": false},  # Normal
	{"aim_jitter": 0.015, "turn_scale": 1.50, "lead": 0.8, "reaction": 0.30, "pause": 0.6,  "tactics": false, "team": true},   # Medium
	# T282 (user 2026-11-05: "Hard will have no intentional bad strategy/aiming errors, elite will be
	# that plus upgrades"; "elite bots don't miss, and in fact shoot ahead of moving targets"): Hard
	# now plays exactly like Elite did -- no aim drift, full lead, no burst pauses, jukes; ELITE is
	# Hard + pilot upgrades ("upgrades": the named elite pilots of T325).
	{"aim_jitter": 0.0,   "turn_scale": 4.00, "lead": 1.0, "reaction": 0.08, "pause": 0.0,  "tactics": true,  "team": true, "juke": true},   # Hard
	{"aim_jitter": 0.0,   "turn_scale": 4.00, "lead": 1.0, "reaction": 0.08, "pause": 0.0,  "tactics": true,  "team": true, "juke": true, "upgrades": true},  # Elite
]
# T172: roles by team slot (Arena: bot_id = 1 + team*100 + slot), not RNG: a random
# 2:1:1 roll could make a whole team defenders. Team presets drop the idle defender.
const ROLES_SOLO: Array = ["attacker", "attacker", "flanker", "defender"]
const ROLES_TEAM: Array = ["attacker", "attacker", "flanker", "attacker"]

# Role: "attacker" pushes enemy beacons, "defender" guards own beacons,
# "flanker" prioritises neutral beacons and approaches from the side.
var role: String = "attacker"
var personality: Dictionary = {}  # T350: an Elite pilot's {role, range_k, retreat_hp} (BotNames.ELITE_KIT)

var _target: Node3D = null
var _prev_target: Node3D = null  # T172: change detector for the reaction delay
var _react_timer: float = 0.0
var _threat: Node3D = null       # T169: who shot us last
var _threat_timer: float = 0.0
var _retaliate_cd: float = 0.0
var _beacons: Array = []
var _own_team: int = 1
var _claimed_beacon: Node = null   # beacon we told AIDirector we're heading to
var _look_delta: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.ZERO
var _firing: bool = false
var _ability_press: bool = false
var _reload_press: bool = false
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
var _los_blocked_time: float = 0.0  # seconds target has been LoS-blocked; drops target at 1s
var _rng: RandomNumberGenerator  # T98: seeded per-bot RNG; MP seed set by T104
var bot_id: int = 0  # T104: unique bot id set by Arena at spawn; used for seed derivation
var difficulty: int = -1  # T172: per-bot override (bot_eval); -1 = Game.settings bot_difficulty

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	# M0.1: no randomize() -- that reseeds from system entropy and kills
	# determinism. The real per-bot seed arrives via set_mp_seed() in
	# Match._apply_bot_seeds(); bot_id makes each bot's stream distinct.
	_rng.seed = bot_id
	add_to_group("ai_input_sources")
	call_deferred("_find_targets")

# T104: called by Match._apply_bot_seeds() on all peers to sync bot RNG.
func set_mp_seed(seed: int) -> void:
	_rng.seed = seed

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		Game.ai_director_clear_intent(get_parent())

func _preset() -> Dictionary:
	var i: int = difficulty if difficulty >= 0 else Game.settings.get("bot_difficulty", 1)
	return DIFFICULTY_PRESETS[clampi(i, 0, DIFFICULTY_PRESETS.size() - 1)]

func _find_targets() -> void:
	_own_team = get_parent().get("team") if get_parent() != null else 1
	_beacons = get_tree().get_nodes_in_group("beacons")
	var roles: Array = ROLES_TEAM if _preset()["team"] else ROLES_SOLO
	role = roles[posmod(bot_id - 1, 100) % roles.size()]
	role = String(personality.get("role", role))  # T350
	# Re-evaluate target immediately when this bot takes damage (B26).
	var pawn := get_parent().get("pawn") as Node
	if pawn != null and pawn.has_signal("damaged"):
		pawn.damaged.connect(_on_pawn_damaged)

# T169: shot by someone other than our target -> turn on them now, unless we're about
# to finish the current target. Either way the attacker scores a bonus for a while.
# T172 (team presets): nearby teammates hear about the attacker too.
func _on_pawn_damaged() -> void:
	var pawn: Node = get_parent().get("pawn")
	var atk = pawn.get("last_attacker") if pawn != null else null  # untyped: may be freed
	if not _is_live_enemy(atk):
		_target_refresh = 0.0
		return
	if _preset()["team"] and pawn is Node3D:
		for ai in get_tree().get_nodes_in_group("ai_input_sources"):
			if ai == self or ai.get("_own_team") != _own_team or not ai.has_method("hear_threat"):
				continue
			var mate = ai.get_parent().get("pawn")
			if mate is Node3D and is_instance_valid(mate) \
					and (mate as Node3D).global_position.distance_to((pawn as Node3D).global_position) < HELP_RADIUS:
				ai.hear_threat(atk)
	_threat = atk
	_threat_timer = THREAT_MEMORY
	if _preset().get("juke", false) and _strafe_timer > 0.25:
		_strafe_sign = -_strafe_sign
		_strafe_timer = _rng.randf_range(0.4, 0.9)
	if atk == _target or _retaliate_cd > 0.0:
		return
	if _is_live_enemy(_target) and _hp_pct(_target) < FINISH_HP and _has_clear_shot:
		return
	_target = atk
	_target_refresh = 2.0
	_retaliate_cd = RETALIATE_CD
	_los_blocked_time = 0.0

## T172: a teammate within HELP_RADIUS is being shot by `atk`. Bonus it; re-pick now
## unless we're already trading shots with someone.
func hear_threat(atk) -> void:
	if not _is_live_enemy(atk):
		return
	_threat = atk
	_threat_timer = THREAT_MEMORY
	if not (_is_live_enemy(_target) and _has_clear_shot):
		_target_refresh = 0.0

func _is_live_enemy(m) -> bool:
	return m != null and is_instance_valid(m) and m.visible and not m.get("is_dead") \
		and not m.get("is_stealthy") and m.get("team") != _own_team

func _hp_pct(m: Node) -> float:
	return clampf(m.health / maxf(float(m.get("max_health") if m.get("max_health") != null else 1.0), 1.0), 0.0, 1.0)

# High score = close + low HP + recent attacker (T169).
# T172 team presets: + in sight, + teammates already shooting it (focus fire).
# T219: distance 0.3/m (was 0.1): a fresh enemy 25 m off lost to a hurt one 60 m off by
# ~3 points and the +2 switching hysteresis kept the far one -- idle bots ignored who was
# closest. Full HP difference (12) now buys ~40 m, not 120 m.
const DIST_WEIGHT := 0.3

func _score(from: Node3D, em: Node3D) -> float:
	var d := from.global_position.distance_to(em.global_position)
	var score := (1.0 - _hp_pct(em)) * 12.0 - d * DIST_WEIGHT
	if d < CLOSE_RANGE:  # T190: whoever walked up to us is the threat, LOS or not
		score += CLOSE_BONUS * (1.0 - d / CLOSE_RANGE)
	if em == _threat and _threat_timer > 0.0:
		score += THREAT_BONUS
	if _preset()["team"]:
		if _los_to(from, em):
			score += VISIBLE_BONUS
		score += FOCUS_BONUS * mini(_mates_on(em), 3)
	return score

var _close_check := 0.0
var _close_seen: Node3D = null

func _nearest_enemy(from: Node3D) -> Node3D:
	var best: Node3D = null
	for em in get_tree().get_nodes_in_group("mechs"):
		if _is_live_enemy(em) and (best == null or from.global_position.distance_to(em.global_position) \
				< from.global_position.distance_to(best.global_position)):
			best = em
	return best

func _mates_on(em: Node) -> int:
	var n := 0
	for ai in get_tree().get_nodes_in_group("ai_input_sources"):
		if ai != self and ai.get("_own_team") == _own_team and ai.get("_target") == em:
			n += 1
	return n

# Picks the best target. Scans the live group, not a spawn-time list (T169: squad
# respawns and late bot takeovers were invisible to bots spawned earlier).
func _pick_best_target(from: Node3D) -> Node3D:
	var best: Node3D = null
	var best_score := -INF
	for em in get_tree().get_nodes_in_group("mechs"):
		if not _is_live_enemy(em):
			continue
		var score := _score(from, em)
		if score > best_score:
			best_score = score
			best = em
	return best

## T189: nearest live teammate (bot or human) when the fight here is clearly lost on
## numbers -- 2+ more enemies than friends (self included) within OUTNUMBER_RADIUS; else
## null. A plain majority made the smaller team fall back all match and ball up.
func _fallback_ally(bot_mech: Node3D) -> Node3D:
	var pos := bot_mech.global_position
	var foes := 0
	var friends := 1
	var nearest: Node3D = null
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == bot_mech or m.get("is_dead") or not (m as Node3D).visible:
			continue
		var d: float = pos.distance_to((m as Node3D).global_position)
		if m.get("team") == _own_team:
			friends += int(d < OUTNUMBER_RADIUS)
			if nearest == null or d < pos.distance_to(nearest.global_position):
				nearest = m
		elif d < OUTNUMBER_RADIUS:
			foes += 1
	return nearest if foes >= friends + 2 else null

func _pick_target_beacon(bot_mech: Node3D) -> Node:
	var best: Node = null
	var best_score := -INF
	# T189: every role pays the crowd penalty (2 bots per beacon free), so a team spreads
	# over the beacons instead of rushing one together (T172's shared attacker objective).
	var from: Vector3 = bot_mech.global_position
	for b in _beacons:
		if not is_instance_valid(b):
			continue
		# Skip beacons in the stuck zone.
		if _avoid_timer > 0.0 and \
				Vector2(b.global_position.x - _avoid_zone.x, b.global_position.z - _avoid_zone.z).length() < AVOID_RADIUS:
			continue
		var owner: int = b.get("owner_team") if b.get("owner_team") != null else -1
		var dist: float = from.distance_to(b.global_position)
		var priority: float
		match role:
			"defender":
				if owner == _own_team:
					priority = 15.0
				elif owner == -1:
					priority = 3.0
				else:
					priority = 1.0
			"flanker":
				if owner == -1:
					priority = 14.0
				elif owner == 1 - _own_team:
					priority = 6.0
				else:
					continue
			_: # "attacker"
				if owner == _own_team:
					continue
				priority = 10.0 if owner == -1 else 5.0
		# T189: count the OTHER bots on it -- our own claim used to count against us, so a
		# bot flip-flopped between beacons; a small bonus keeps a claim unless clearly beaten.
		var others: int = Game.ai_director_intent_count(b, _own_team) - int(b == _claimed_beacon)
		var crowd_penalty := maxf(0.0, float(others - 1)) * 5.0
		var score: float = priority - dist * 0.05 - crowd_penalty + (CLAIM_STICKY if b == _claimed_beacon else 0.0)
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
		Game.ai_director_set_intent(get_parent(), beacon, _own_team)
	else:
		Game.ai_director_clear_intent(get_parent())

## True when no collideable geometry lies between `from`'s eye and `em`'s centre.
## Same PhysicsRayQueryParameters3D pattern as the weapon scripts.
func _los_to(from: Node3D, em: Node3D) -> bool:
	var eye: Vector3 = from.global_position + Vector3(0, 2.0, 0)
	var tgt: Vector3 = em.global_position + Vector3(0, 1.5, 0)
	var query := PhysicsRayQueryParameters3D.create(eye, tgt)
	query.exclude = from.get_exclude_rids()
	var result := from.get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	# T172: the target's own parts count (its PhysicalShield is a child StaticBody3D;
	# shields read as walls, so shielded mechs were "unseen" point-blank)
	var col = result.get("collider")
	return col == em or (col is Node and em.is_ancestor_of(col))

func _check_los(bot_mech: Node3D) -> void:
	if _target == null or not is_instance_valid(_target) or not _target.visible:
		_has_clear_shot = false
		_los_blocked_time = 0.0
		return
	_has_clear_shot = _los_to(bot_mech, _target)
	if _has_clear_shot:
		_los_blocked_time = 0.0
	else:
		_los_blocked_time += LOS_INTERVAL
		# T172 tactics: hold the target 3 s (we chase it) instead of 1 s
		if _los_blocked_time >= (3.0 if _preset()["tactics"] else 1.0):
			_target = null
			_target_refresh = 0.0
			_los_blocked_time = 0.0

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

## World-space direction -> move input relative to the mech's aim basis.
func _to_move(bot_mech: Node3D, dir: Vector3) -> Vector2:
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return Vector2.ZERO
	var aim_basis: Basis = bot_mech.call("get_aim_basis")
	return Vector2(dir.dot(aim_basis.x), -dir.dot(-aim_basis.z)).normalized()

## Move input toward goal_pos along the nav path (direct steering until the navmesh is ready).
## T172: "arrived" = near the GOAL in plan view. A waypoint straight below/above (step
## riser) is < 1.5 m flat but > path_desired_distance in 3D, so the agent never advanced
## past it and the old `steer.length() > 1.5` check stood the bot still for good.
func _steer_to(bot_mech: Node3D, goal_pos: Vector3) -> Vector2:
	var to_goal := goal_pos - bot_mech.global_position
	to_goal.y = 0.0
	if to_goal.length() <= 1.5:
		return Vector2.ZERO
	var next := _nav_next(bot_mech, goal_pos)
	var steer: Vector3 = (next if next != Vector3.ZERO else goal_pos) - bot_mech.global_position
	steer.y = 0.0
	return _to_move(bot_mech, steer if steer.length() > 0.3 else to_goal)

# Runs at physics rate: Mech._handle_look consumes _look_delta once per physics
# tick, so computing it here (with the fixed physics delta) keeps bot turn speed
# independent of render frame rate. Also keeps per-tick RNG draws deterministic.
func _physics_process(delta: float) -> void:
	if not Game.prof_on:  # T165 profiling shim
		_physics_process_impl(delta)
		return
	var t0 := Time.get_ticks_usec()
	_physics_process_impl(delta)
	Game.prof_add("ai", Time.get_ticks_usec() - t0)

func _primary(bot_mech: Node) -> Node:
	for w in bot_mech.get_weapons():
		if is_instance_valid(w):
			return w
	return null

## T169: fire out to half the longest weapon's range (snipers/rockets reach), never under the old 50 m.
## T172 tactics: the weapon's real reach (projectiles expire at range).
func _fire_range(bot_mech: Node) -> float:
	var tactics: bool = _preset()["tactics"]
	var r := 0.0 if tactics else ENGAGE_DIST + 15.0
	for w in bot_mech.get_weapons():
		if is_instance_valid(w) and "range" in w:
			# T339: a lock (built only inside the weapon's range, T334) is reason enough to fire
			r = maxf(r, float(w.range) * (0.95 if tactics or w.get("requires_lock") == true else 0.5))
	return r

## T172: distance a bot with this weapon fights from (shotgun close, sniper far).
func _pref_range(w: Node) -> float:
	if w == null:
		return 30.0
	if "pellet_count" in w:
		return 9.0
	return clampf(float(w.range) * 0.45, 10.0, 60.0) * float(personality.get("range_k", 1.0))  # T350

## T172: where to aim -- target centre plus `lead` x its motion over the shot's flight time.
## Homing (lock) weapons and beams don't lead.
func _aim_point(bot_mech: Node3D, w: Node, lead: float) -> Vector3:
	var c: Vector3 = _target.call("center_mass") if _target.has_method("center_mass") else _target.to_global(Vector3.UP)  # T319
	if lead <= 0.0 or w == null or not ("projectile_speed" in w) or w.requires_lock:
		return c
	var spd: float = maxf(float(w.projectile_speed), 1.0)
	var v: Vector3 = _target.get("velocity") if _target.get("velocity") != null else Vector3.ZERO
	var muzzle: Vector3 = bot_mech.global_position + Vector3.UP * 2.0
	var p := c
	for i in 2:
		p = c + v * (muzzle.distance_to(p) / spd) * lead
	return p

func _physics_process_impl(delta: float) -> void:
	# T40: bots run server-only; clients receive mech state via replication, not AI.
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	var bot_mech: Node3D = get_parent().get("pawn")
	if bot_mech == null:
		_look_delta = Vector2.ZERO
		_move_dir   = Vector2.ZERO
		_firing     = false
		return

	var preset: Dictionary = _preset()
	var tactics: bool = preset["tactics"]
	_threat_timer -= delta
	_retaliate_cd -= delta
	_react_timer -= delta
	# T190: an enemy stepping in close forces a re-pick now, not at the next 2 s refresh
	_close_check -= delta
	if _close_check <= 0.0:
		_close_check = 0.25
		var near := _nearest_enemy(bot_mech)
		if near != null and bot_mech.global_position.distance_to(near.global_position) >= CLOSE_RANGE:
			near = null
		if near != null and near != _target and near != _close_seen:
			_target_refresh = 0.0  # once per close arrival; hysteresis may still keep the old target
		_close_seen = near
	# Refresh target periodically or when current target is no longer valid.
	_target_refresh -= delta
	if _target_refresh <= 0.0 or not is_instance_valid(_target) or not _target.visible:
		_target_refresh = 2.0
		var new_target := _pick_best_target(bot_mech)
		if new_target != null and new_target != _target and _is_live_enemy(_target):
			# Hysteresis: switch only for a clearly better target (+2 score; the old
			# `* 1.25` made switching easier, not harder, for the usual negative scores).
			if _score(bot_mech, new_target) <= _score(bot_mech, _target) + 2.0:
				new_target = _target
		_target = new_target

	# Periodically check line-of-sight to target.
	_los_timer -= delta
	if _los_timer <= 0.0:
		_los_timer = LOS_INTERVAL
		_check_los(bot_mech)

	var has_target: bool = _target != null and is_instance_valid(_target) and _target.visible and not _target.get("is_stealthy")
	if not has_target:
		_target = null
	# T172: a new target costs a reaction delay before the first shot.
	if _target != _prev_target:
		_prev_target = _target
		if _target != null:
			_react_timer = float(preset["reaction"]) * (1.0 + 0.5 * _rng.randf())
	var sens: float = Game.settings.get("mouse_sensitivity", 0.003)
	var aim_jitter: float = preset["aim_jitter"]
	var eff_turn: float = TURN_SPEED * preset["turn_scale"]
	var weapon := _primary(bot_mech)
	var fire_range := _fire_range(bot_mech)

	var angle_h := 0.0
	var dist := INF
	var aim_p := Vector3.ZERO

	if has_target:
		dist = (_target.global_position - bot_mech.global_position).length()
		aim_p = _aim_point(bot_mech, weapon, preset["lead"])
		var to_target := aim_p - bot_mech.global_position

		# Horizontal aim
		var to_flat := Vector3(to_target.x, 0.0, to_target.z)
		var h_dist  := to_flat.length()
		if h_dist > 0.01:
			to_flat = to_flat / h_dist
			angle_h = (-bot_mech.get_aim_basis().z).signed_angle_to(to_flat, Vector3.UP)
		angle_h += _jitter.x
		var max_turn_h: float = eff_turn * delta
		var turn_h: float = clamp(angle_h * 0.5, -max_turn_h, max_turn_h)
		_look_delta.x = -turn_h / sens

		# Vertical aim
		var cam_arm := bot_mech.get_node_or_null("Torso/CameraArm") as SpringArm3D
		var cam     := bot_mech.get_node_or_null("Torso/CameraArm/Camera3D") as Camera3D
		if cam_arm and cam:
			var cam_to_target := aim_p - cam.global_position
			var cam_h_dist: float = Vector2(cam_to_target.x, cam_to_target.z).length()
			var desired_pitch: float = atan2(cam_to_target.y, maxf(cam_h_dist, 0.01))
			var pitch_diff: float    = desired_pitch - cam_arm.rotation.x + _jitter.y
			var turn_v: float        = clamp(pitch_diff * 0.5, -eff_turn * delta, eff_turn * delta)
			_look_delta.y = -turn_v / sens
	else:
		_look_delta = Vector2.ZERO
		_firing = false

	var own_max_hp: float = maxf(bot_mech.get("max_health") if bot_mech.get("max_health") != null else 1.0, 1.0)
	var own_hp_pct: float = clampf(bot_mech.health / own_max_hp, 0.0, 1.0)
	if tactics:
		_update_rwf(weapon)  # T359: hold / press on / back off with a reload-while-firing gun
	var pickup := wanted_pickup(bot_mech, has_target, dist, fire_range, own_hp_pct, tactics)
	if pickup != null:
		_move_dir = _steer_to(bot_mech, pickup.global_position)  # T352
	elif tactics:
		_move_dir = _tactical_move(bot_mech, has_target, dist, fire_range, weapon, own_hp_pct, delta)
	else:
		_move_dir = _legacy_move(bot_mech, has_target, dist, own_hp_pct, delta)

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
		# T172: a third of the distance this mech should cover; the flat 0.5 m read every
		# mech under 1 m/s (Warhog 0.9, Everest 0.75) as permanently stuck.
		var stuck_dist: float = minf(STUCK_DIST, float(bot_mech.get("walk_speed")) * STUCK_CHECK * 0.35)
		if _move_dir != Vector2.ZERO and \
				bot_mech.global_position.distance_to(_last_pos) < stuck_dist:
			_stuck_count += 1
			_escape_timer = minf(ESCAPE_TIME * _stuck_count, ESCAPE_TIME_MAX)
			var side := 1.0 if _rng.randf() > 0.5 else -1.0
			if _stuck_count <= 1:
				# First escape: sideways strafe
				_escape_vec = Vector2(side, -0.3).normalized()
			elif _stuck_count <= 2:
				# Second escape: back up with a sideways component
				_escape_vec = Vector2(side * 0.4, 0.9).normalized()
			else:
				# Repeated stuck: fully random direction to break the oscillation
				var angle := _rng.randf_range(0.0, TAU)
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

	_ability_press = false
	_reload_press = false
	if has_target:
		# Aim jitter - slow random drift that makes the bot miss occasionally
		_jitter_timer -= delta
		if _jitter_timer <= 0.0:
			_jitter_timer = _rng.randf_range(0.08, 0.18)
			_jitter = Vector2(_rng.randf_range(-aim_jitter, aim_jitter),
							  _rng.randf_range(-aim_jitter, aim_jitter))
		# Burst fire - shoot for BURST_FIRE seconds, pause for BURST_PAUSE x preset pause
		var pause: float = BURST_PAUSE * float(preset["pause"])
		if pause <= 0.0:
			_in_burst = true
		else:
			_burst_timer -= delta
			if _burst_timer <= 0.0:
				_in_burst = not _in_burst
				_burst_timer = BURST_FIRE if _in_burst else pause
		var ready: bool = _in_burst and dist < fire_range and _has_clear_shot and _react_timer <= 0.0
		if tactics:
			_firing = ready and _shot_worth_taking(bot_mech, weapon, aim_p) and not rwf_hold  # T359
		else:
			# Fire when aimed closely enough, in range, in burst window, and LOS is clear.
			_firing = ready and abs(angle_h) < AIM_THRESHOLD
	if tactics:
		_use_abilities(bot_mech, has_target and dist < fire_range, own_hp_pct, has_target, dist, fire_range)
		if not has_target:
			_reload_press = _wants_reload(bot_mech)

## T352 (HUMAN_FOUND 2026-11-08: "bots go for powerups but can't pick up coins"): a bot detours
## to a powerup close by -- a repair kit when hurt (Hard / Elite from further, even mid-fight), any
## other one when nothing is in range to fight. Coins are left for the players.
const PICKUP_SEEK_M := 25.0
const REPAIR_SEEK_M := 45.0

func wanted_pickup(bot_mech: Node3D, has_target: bool, dist: float, fire_range: float,
		own_hp_pct: float, tactics: bool) -> Node3D:
	var fighting := has_target and dist < fire_range
	var best: Node3D = null
	var best_d := INF
	for p in bot_mech.get_tree().get_nodes_in_group("pickups"):
		var kind: String = p.get("kind")
		if kind == "coin" or p.get("collected"):
			continue
		var reach := 0.0
		if kind == "repair":
			if own_hp_pct < 0.6:
				reach = REPAIR_SEEK_M if tactics else PICKUP_SEEK_M
			elif own_hp_pct < 0.95 and not fighting:
				reach = PICKUP_SEEK_M
		elif not fighting:
			reach = PICKUP_SEEK_M if tactics else PICKUP_SEEK_M * 0.6
		var d := bot_mech.global_position.distance_to((p as Node3D).global_position)
		if d < reach and d < best_d:
			best = p
			best_d = d
	return best

## T359 (user 2026-11-08: bots "continue firing with reload-while-firing weapons that are empty ...
## should probably only be for hard and elite"; then "RWF bots shouldn't always wait until they are
## full, rather, be smart about it (press forward if enemy has low health, hide if enemy has a
## reload-while-empty weapon, burst for a few shots, etc.)"): with a REFILLING gun, Hard / Elite fire
## down to RWF_LOW, then hold fire until it's back to RWF_RESUME (a burst's worth, not full) -- unless
## the target is nearly dead (press on). While holding against a target with a FIXED (reload-when-
## empty) gun they also give ground (the retreat strafe), out of its next full magazine.
const RWF_LOW := 0.15
const RWF_RESUME := 0.4      # calibration knob
const RWF_FINISH_HP := 0.25  # target health share that's worth emptying the gun for
var rwf_hold := false
var rwf_cover := false

func _update_rwf(w: Node) -> void:
	rwf_cover = false
	if w == null or not is_instance_valid(w) or int(w.get("max_ammo")) <= 0 or int(w.get("magazine_type")) != 1:
		rwf_hold = false
		return
	var t_ok := _target != null and is_instance_valid(_target)
	if t_ok and float(_target.get("health")) < RWF_FINISH_HP * maxf(float(_target.get("max_health")), 1.0):
		rwf_hold = false  # nearly dead: press on
		return
	var frac := float(w.get("ammo")) / float(w.get("max_ammo"))
	if not rwf_hold and frac <= RWF_LOW:
		rwf_hold = true
	elif rwf_hold and frac >= RWF_RESUME:
		rwf_hold = false
	if rwf_hold and t_ok and _target.has_method("get_weapons"):
		for tw in _target.get_weapons():
			if is_instance_valid(tw) and int(tw.get("max_ammo")) > 0 and int(tw.get("magazine_type")) == 0:
				rwf_cover = true

## Pre-T172 movement (Easy..Medium): beacon routing, back off when crowded, flee when low.
func _legacy_move(bot_mech: Node3D, has_target: bool, dist: float, own_hp_pct: float, delta: float) -> Vector2:
	var role_retreat_dist := RETREAT_DIST * (1.5 if role == "defender" else 1.0)
	if own_hp_pct < 0.20 and has_target:
		return _to_move(bot_mech, bot_mech.global_position - _target.global_position)
	if has_target and dist < role_retreat_dist:
		_claim_beacon(null)
		return Vector2(0.0, 1.0)
	var beacon := _pick_target_beacon(bot_mech)
	_claim_beacon(beacon)
	if beacon != null:
		return _steer_to(bot_mech, beacon.global_position)
	if has_target:
		# All beacons owned - circle-strafe and fight.
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(1.5, 3.0)
			_strafe_sign  = 1.0 if _rng.randf() > 0.5 else -1.0
		if dist > ENGAGE_DIST:
			return Vector2(0.0, -1.0)
		return Vector2(_strafe_sign, -0.3).normalized()
	var near := _nearest_enemy(bot_mech)  # T285: no beacons (death match) -> hunt
	return _steer_to(bot_mech, near.global_position) if near != null else Vector2.ZERO

## T172 (Hard, Elite). In a fight: hold the weapon's preferred range and strafe (slow
## projectiles miss a sidestepping mech), keep capturing a contested objective underfoot,
## back off when hurt. Target out of sight: chase it. Otherwise: objective beacon, with
## the pack (wait when far ahead), or hunt the nearest enemy once every beacon is ours.
func _tactical_move(bot_mech: Node3D, has_target: bool, dist: float, fire_range: float,
		weapon: Node, own_hp_pct: float, delta: float) -> Vector2:
	var beacon := _pick_target_beacon(bot_mech)
	_claim_beacon(beacon)
	var pos := bot_mech.global_position
	var ally: Node3D = _fallback_ally(bot_mech) if _preset()["team"] else null
	if has_target and _has_clear_shot and dist < fire_range * 1.1:
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_timer = _rng.randf_range(0.5, 1.4)
			_strafe_sign = 1.0 if _rng.randf() > 0.5 else -1.0
		var to_t := _target.global_position - pos
		to_t.y = 0.0
		to_t = to_t.normalized()
		var side := Vector3(-to_t.z, 0.0, to_t.x) * _strafe_sign
		if beacon != null and beacon.get("owner_team") != _own_team:
			var to_b: Vector3 = beacon.global_position - pos
			to_b.y = 0.0
			if to_b.length() < 10.0:  # capture while fighting: stay on the circle
				return _to_move(bot_mech, to_b.normalized() + side * 0.6) if to_b.length() > 2.0 else _to_move(bot_mech, side)
		var pref := _pref_range(weapon)
		var radial := 0.0
		var retreat := own_hp_pct < float(personality.get("retreat_hp", 0.3)) or ally != null or rwf_cover  # T189: outnumbered -> give ground too; T359
		if retreat:
			radial = -1.0
		elif dist < pref * 0.7:
			radial = -0.6
		elif dist > pref * 1.15 and beacon == null:
			radial = 1.0
		var move := to_t * radial + side * 0.9
		# T189: fight on the way to your own objective. Everyone shares the focus target, so
		# range-keeping on it alone pulled the whole team into one clump.
		if not retreat and beacon != null and beacon.get("owner_team") != _own_team:
			var nxt := _nav_next(bot_mech, beacon.global_position)  # around walls, not into them
			var to_obj: Vector3 = (nxt if nxt != Vector3.ZERO else beacon.global_position) - pos
			to_obj.y = 0.0
			move += to_obj.normalized()
		return _to_move(bot_mech, move)
	if has_target and not _has_clear_shot and dist < CHASE_DIST:
		return _steer_to(bot_mech, _target.global_position)
	var goal: Vector3 = beacon.global_position if beacon != null else Vector3(INF, 0.0, INF)
	if beacon == null:
		var near := _nearest_enemy(bot_mech)
		if near == null:
			return Vector2.ZERO
		goal = near.global_position
	if ally != null and pos.distance_to(ally.global_position) > 15.0:
		return _steer_to(bot_mech, ally.global_position)  # T189: regroup only when outnumbered
	return _steer_to(bot_mech, goal)

## T172 tactics: only pull the trigger when the shot can land -- aim within a body
## width of the (led) target, a lock for lock weapons, a full Patience charge.
func _shot_worth_taking(bot_mech: Node3D, w: Node, aim_p: Vector3) -> bool:
	if w == null:
		return false
	if w.requires_lock:
		var lt = bot_mech.get("locked_target")
		return lt != null and is_instance_valid(lt)
	if w.has_method("get_charge_progress") and w.get_charge_progress() < 0.9:
		return false
	var cam: Camera3D = bot_mech.get("camera")
	if cam == null:
		return true
	var to_p := aim_p - cam.global_position
	var miss := sin((-cam.global_transform.basis.z).angle_to(to_p)) * to_p.length()
	var scale: float = _target.global_transform.basis.get_scale().x
	return miss < 0.9 * scale + to_p.length() * 0.01

## T172 tactics: jump-heal when it heals in full (or when hurt in a fight), cloak to
## ambush or escape. Presses only off cooldown (each press is a sync-log event).
func _use_abilities(bot_mech: Node3D, fighting: bool, own_hp_pct: float, has_target := false,
		dist := INF, fire_range := 0.0) -> void:
	var cds: Dictionary = bot_mech.get("_ability_cooldowns")
	var active: Dictionary = bot_mech.get("_ability_active_timers")
	for ab in bot_mech.get("_abilities"):
		var key: String = ab.effect_key
		if cds.get(key, 0.0) > 0.0 or active.get(key, 0.0) > 0.0:
			continue
		match key:
			"jump_heal":
				_ability_press = bot_mech.health <= bot_mech.max_health - 80.0 or (fighting and own_hp_pct < 0.6)
			"stealth":
				_ability_press = stealth_wanted(bot_mech, has_target, dist, fire_range, own_hp_pct)
			"lunge":
				_ability_press = lunge_wanted(bot_mech, has_target, dist)

## T342: ram a target that's straight ahead inside the dash's reach (~15 m) with a clear line
## (the LoS check doubles as "no wall in the way"); not point-blank, where the windup wastes it.
const LUNGE_MIN_M := 5.0
const LUNGE_MAX_M := 15.0
const LUNGE_AIM_RAD := 0.12

func lunge_wanted(bot_mech: Node3D, has_target: bool, dist: float) -> bool:
	if not has_target or not _has_clear_shot or dist < LUNGE_MIN_M or dist > LUNGE_MAX_M:
		return false
	var to := _target.global_position - bot_mech.global_position
	to.y = 0.0
	var fwd: Vector3 = -(bot_mech.get_aim_basis() as Basis).z
	fwd.y = 0.0
	return to.length() > 0.01 and fwd.angle_to(to) < LUNGE_AIM_RAD

## T295 (HUMAN_FOUND 2026-11-05 late: "Cesh bots should use stealth more intelligently"): cloak
## for a reason, not whenever a fight is on (24 s on, 24 s off) -- to close in on a target still
## out of range, to shake an enemy lock (built or building), to slip away hurt, or to cross open
## ground to a beacon the team doesn't hold. Trading shots in range at good health: stay visible.
const STEALTH_CLOSE_K := 2.5     # approach: target within this x weapon range, not yet in range
const STEALTH_LOCK_PROGRESS := 0.4
const STEALTH_BEACON_M := Vector2(25.0, 90.0)

func stealth_wanted(bot_mech: Node3D, has_target: bool, dist: float, fire_range: float,
		own_hp_pct: float) -> bool:
	if own_hp_pct < 0.4 and has_target:
		return true
	if has_target and dist > fire_range and dist < fire_range * STEALTH_CLOSE_K:
		return true
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == bot_mech or not _is_live_enemy(m):
			continue
		if m.get("locked_target") == bot_mech:
			return true
		if m.get("_lock_candidate") == bot_mech and float(m.get("lock_progress")) >= STEALTH_LOCK_PROGRESS:
			return true
	if not has_target and is_instance_valid(_claimed_beacon) and _claimed_beacon.get("owner_team") != _own_team:
		var d := bot_mech.global_position.distance_to(_claimed_beacon.global_position)
		return d > STEALTH_BEACON_M.x and d < STEALTH_BEACON_M.y
	return false

## T172 tactics: top up a fixed magazine below half while nothing is in sight.
func _wants_reload(bot_mech: Node) -> bool:
	for w in bot_mech.get_weapons():
		if is_instance_valid(w) and w.max_ammo > 0 and w.magazine_type == 0 \
				and not w.is_reloading() and w.ammo < w.max_ammo * 0.5:
			return true
	return false

func get_move_direction() -> Vector2:
	return _move_dir

func get_look_delta() -> Vector2:
	# Drain on read (same pattern as PlayerInputSource/NetworkInputSource) so a
	# turn impulse is never applied twice if a tick ever reads without a fresh write.
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d

func is_firing_primary() -> bool:
	return _firing

func is_ability_pressed() -> bool:
	return _ability_press

func is_reload_pressed() -> bool:
	return _reload_press
