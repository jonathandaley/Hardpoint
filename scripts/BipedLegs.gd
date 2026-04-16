class_name BipedLegs
extends Node3D
# Two-legged mech leg controller. Attach to the Legs node in a biped mech scene.
#
# Responsibilities:
#   1. Rotate the whole Legs node to face the mech's velocity direction.
#   2. Drive the walk-cycle animation by rotating hip and knee pivots.
#
# Called by Mech._update_legs() each physics tick via:
#   legs.call("update_gait", velocity, mech_basis, leg_rotation_speed, delta)
#
# For a four-legged mech, create QuadLegs.gd with the same update_gait()
# signature and attach it to that mech's Legs node instead.

# Rest-pose rotations baked into the scene (X axis only).
const REST_HIP   := 0.524
const REST_KNEE1 := -2.094
const REST_KNEE2 :=  2.094

# Walk-cycle tuning.
const HIP_SWING   := 0.22   # rad  - hip fore/aft amplitude
const KNEE_LIFT   := 0.55   # rad  - top-knee flex at peak of swing arc
const STANCE_FLEX := 0.08   # rad  - slight knee bend at mid-stance
const BODY_BOB    := 0.06   # m    - torso vertical bob amplitude
const CYCLE_RATE  := 1.8    # rad of phase per metre of travel

@onready var left_hip:    Node3D = $LeftHip
@onready var right_hip:   Node3D = $RightHip
@onready var left_knee1:  Node3D = get_node("LeftHip/LeftKnee1")
@onready var left_knee2:  Node3D = get_node("LeftHip/LeftKnee1/LeftKnee2")
@onready var right_knee1: Node3D = get_node("RightHip/RightKnee1")
@onready var right_knee2: Node3D = get_node("RightHip/RightKnee1/RightKnee2")

var _torso: Node3D = null
var _phase: float = 0.0

func update_gait(velocity: Vector3, mech_basis: Basis, rot_speed: float, delta: float) -> void:
	if _torso == null:
		_torso = get_parent().get_node_or_null("Torso") as Node3D
	_face_velocity(velocity, mech_basis, rot_speed, delta)
	_animate_walk(velocity, delta)

func _animate_walk(velocity: Vector3, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed  := horiz.length()
	_phase = fposmod(_phase + speed * CYCLE_RATE * delta, TAU)

	# Blend amplitude 0->1 over the first 1 m/s so joints return to rest when idle.
	var t  := clampf(speed, 0.0, 1.0)
	var sl := sin(_phase)
	var sr := sin(_phase + PI)

	# Body bob - torso dips at transition points (inverted-pendulum walk).
	if _torso != null:
		_torso.position.y = -BODY_BOB * abs(sl) * t

	# Hip drive: -cos separates fore/aft sweep from the lift.
	# phase=0: back(liftoff)  phase=PI/2: neutral  phase=PI: forward(heel-strike)
	left_hip.rotation.x  = REST_HIP - cos(_phase)      * HIP_SWING * t
	right_hip.rotation.x = REST_HIP - cos(_phase + PI) * HIP_SWING * t

	# Swing lift: sin arch peaks at mid-swing when hip is at neutral.
	# Foot is at apex while leg is mid-arc, plants at max extension.
	var swing_l: float = maxf(0.0, sl) * t
	var swing_r: float = maxf(0.0, sr) * t

	# Stance bend: slight flex peaks at mid-stance to keep foot travelling level.
	var stance_l: float = maxf(0.0, -sl) * STANCE_FLEX * t
	var stance_r: float = maxf(0.0, -sr) * STANCE_FLEX * t

	var flex_l: float = swing_l * KNEE_LIFT + stance_l
	var flex_r: float = swing_r * KNEE_LIFT + stance_r

	left_knee1.rotation.x  = REST_KNEE1 - flex_l
	right_knee1.rotation.x = REST_KNEE1 - flex_r
	left_knee2.rotation.x  = REST_KNEE2 + flex_l * 0.5
	right_knee2.rotation.x = REST_KNEE2 + flex_r * 0.5

func _face_velocity(velocity: Vector3, mech_basis: Basis, rot_speed: float, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() < 0.25:
		return
	var local_vel := mech_basis.inverse() * horiz
	var target_y  := atan2(-local_vel.x, -local_vel.z)
	var diff       := angle_difference(rotation.y, target_y)
	rotation.y    += clamp(diff, -rot_speed * delta, rot_speed * delta)
