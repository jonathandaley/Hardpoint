extends Node3D
# B145 probe (T429, Jolt): mechs that step into a beacon's zone on the physics step before the
# match ends, then get frozen (Arena.freeze_mechs from a frame callback, the way a match-end RPC
# or timer lands), must not trip Jolt's "ref_count <= 0" area error (the suite fails probes on
# engine ERROR lines). Godot Physics never errored here; the probe matters under Jolt.

var _bodies: Array = []
var _t := 0
var _armed := false

func _ready() -> void:
	var beacon: Node3D = load("res://scenes/beacon/Beacon.tscn").instantiate()
	add_child(beacon)
	for i in 8:
		var b := CharacterBody3D.new()
		b.add_to_group("mechs")
		var c := CollisionShape3D.new()
		c.shape = CapsuleShape3D.new()
		b.add_child(c)
		b.position = Vector3(6.6 + 0.05 * i, 2.0, 0.0)  # just outside the 6 m zone
		add_child(b)
		_bodies.append(b)

func _physics_process(_d: float) -> void:
	_t += 1
	if _t == 10:
		for b in _bodies:
			b.position.x -= 1.0  # into the zone on this step
		_armed = true
	if _t == 30:
		print("[probe] beacon_match_end_freeze done")
		get_tree().quit(0)

func _process(_d: float) -> void:
	if _armed and _t >= 11:  # after the step that saw them enter, before the next flush
		_armed = false
		Arena.freeze_mechs(get_tree(), _bodies)
