extends Node
# T380 probe (HUMAN_FOUND 2026-11-09: Slip legs "make its stride frequency like Cesh's, but with a
# longer step so its speed remains the same"): BipedLegs steps at speed / (J * hip_sweep) * cycle_rate,
# so Slip's cadence at its walk speed matches Cesh's at hers, with the longer step.

func _cadence(md: Resource) -> float:
	return md.walk_speed / md.leg_hip_sweep * md.leg_cycle_rate

func _ready() -> void:
	var slip: Resource = load("res://resources/mechs/Slip.tres")
	var cesh: Resource = load("res://resources/mechs/Cesh.tres")
	var r := _cadence(slip) / _cadence(cesh)
	if absf(r - 1.0) > 0.03:
		push_error("[probe] slip_stride: Slip steps %.2fx as often as Cesh (want 1.0)" % r)
	if slip.leg_hip_sweep <= cesh.leg_hip_sweep or slip.walk_speed != 3.75:
		push_error("[probe] slip_stride: Slip sweep %.3f vs Cesh %.3f, speed %.2f (want a longer step, same speed)"
			% [slip.leg_hip_sweep, cesh.leg_hip_sweep, slip.walk_speed])
	print("[probe] slip_stride done")
	get_tree().quit(0)
