class_name BipedLegs
extends Node3D
# Two-legged mech leg controller. Attach to the Legs node in a biped mech scene.
#
# Responsibilities:
#   1. Rotate the whole Legs node to face the mech's velocity direction.
#   2. Drive the walk-cycle animation (next session) by rotating the
#      hip and knee pivots.
#
# Called by Mech._update_legs() each physics tick via:
#   legs.call("update_gait", velocity, mech_basis, leg_rotation_speed, delta)
#
# For a four-legged mech, create QuadLegs.gd with the same update_gait()
# signature and attach it to that mech's Legs node instead.

@onready var left_hip:   Node3D = $LeftHip
@onready var right_hip:  Node3D = $RightHip
@onready var left_knee:  Node3D = $LeftHip/LeftKnee
@onready var right_knee: Node3D = $RightHip/RightKnee

func update_gait(velocity: Vector3, mech_basis: Basis, rot_speed: float, delta: float) -> void:
	_face_velocity(velocity, mech_basis, rot_speed, delta)
	# Walk cycle animation goes here next session.
	# Will rotate left_hip/right_hip (swing) and left_knee/right_knee (flex)
	# based on a phase offset driven by horizontal speed.

func _face_velocity(velocity: Vector3, mech_basis: Basis, rot_speed: float, delta: float) -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length_squared() < 0.25:
		return
	var local_vel := mech_basis.inverse() * horiz
	var target_y  := atan2(-local_vel.x, -local_vel.z)
	var diff       := angle_difference(rotation.y, target_y)
	rotation.y    += clamp(diff, -rot_speed * delta, rot_speed * delta)
