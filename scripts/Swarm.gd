class_name Swarm
extends "res://scripts/AerialStrike.gd"
# T521 (user 2026-11-19: "Swarm: similar to aerial strike, but the bullets that miss circle around and strike
# again. 10% of hits spawn two more that find another target within 40m and hit that one instead."): the
# aerial strike's locked salvo of homing rockets -- a rocket that misses loops back for another pass (the
# homing it always had) -- plus a split: on an enemy hit, a split_chance roll (server, gameplay RNG) sends
# two fresh rockets from the hit at other enemies within SPLIT_RANGE_M (one each, nearest first; with
# only one other, both go to it). Split rockets never split again. Nobody else in range: no split.

@export var split_chance := 0.10   # calibration knob
const SPLIT_RANGE_M := 40.0
const SPLIT_COUNT := 2

func _spawn_rocket(lock_target: Node3D) -> void:
	super._spawn_rocket(lock_target)
	_arm_split(_last_rocket)

## The server's newest rocket gets the split on its hit (a split rocket is spawned without it).
func _arm_split(proj: Node3D) -> void:
	if proj == null or (multiplayer.has_multiplayer_peer() and not multiplayer.is_server()):
		return
	var base_hit: Callable = proj.on_hit
	proj.on_hit = func(body, pos):
		if base_hit.is_valid():
			base_hit.call(body, pos)
		_maybe_split(body, pos)

func _maybe_split(body, pos: Vector3) -> void:
	if not is_instance_valid(self) or not is_inside_tree() or owner_mech == null:
		return
	var hit_mech: Node = body if body is Node and (body as Node).is_in_group("mechs") else null
	if hit_mech == null or hit_mech.get("team") == owner_mech.get("team"):
		return
	if Game.rng.randf() >= split_chance:
		return
	var others: Array = []
	for m in get_tree().get_nodes_in_group("mechs"):
		if m == hit_mech or m.get("is_dead") or not (m as Node3D).visible or m.get("team") == owner_mech.get("team"):
			continue
		var d := pos.distance_to((m as Node3D).global_position)
		if d <= SPLIT_RANGE_M:
			others.append([d, m])
	if others.is_empty():
		return
	others.sort_custom(func(a, b): return a[0] < b[0])
	for i in SPLIT_COUNT:
		_spawn_split(pos, others[i % others.size()][1])

## A split rocket: from the hit, straight at its new target (no climb), no further split.
func _spawn_split(from: Vector3, target: Node3D) -> void:
	var proj := HOMING_SCENE.instantiate() as Node3D
	proj.damage = damage
	proj.speed = projectile_speed
	proj.lifetime = SPLIT_RANGE_M / projectile_speed + 2.0
	proj.team = owner_mech.get("team") if owner_mech.get("team") != null else 0
	proj._exclude_rids = owner_mech.get_exclude_rids()
	proj.target = target
	proj.owner_body = owner_mech
	proj.source_weapon = self
	proj.arc_time = 0.0
	proj.arc_up_blend = 0.0
	proj.turn_rate = turn_rate * 1.5
	proj.splash_radius = splash_radius
	proj.splash_damage = splash_damage
	proj.on_hit = func(body, p): _emit_hit_if_visible(body, p, true)
	get_tree().current_scene.add_child(proj)
	var up := from + Vector3.UP * 1.5
	proj.global_transform = Transform3D(Basis(), up).looking_at(target.global_position)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_send_ghost(up, proj.global_transform.basis, proj.speed, proj.lifetime, proj.team,
			0.0, 0.0, turn_rate * 1.5, Vector3.ZERO, target.get_path())

func damage_text() -> String:  # T538
	return super.damage_text() + "; misses circle back, %d%% of hits split in two" % roundi(split_chance * 100.0)
