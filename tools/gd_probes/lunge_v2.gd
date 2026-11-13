extends Node
# T404 probe (HUMAN_FOUND, queued 2026-11-13, Taurus lunge physics: "Short crouch anticipation,
# explosive front-loaded acceleration (ease-out), committed momentum with no steering, hard braking
# plant with a slight overshoot and settle ... The \"overshoot\" should be cancelled if it hits a wall
# or mech, so that it just settles out of the impact. Crouch should last .1 seconds."): the lunge curve
# crouches 0.1 s, is near full speed within 0.04 s of the spring, brakes to a stop, rocks back a little
# (negative speed) and settles; a ram / wall skips the rock-back and settles in place; reach ~16 m.

func _fail(msg: String) -> void:
	push_error("[probe] lunge_v2 FAIL: " + msg)

func _ready() -> void:
	var M: Script = load("res://scripts/Mech.gd")
	var c: Dictionary = M.get_script_constant_map()
	var w: float = c["LUNGE_WINDUP_S"]
	var peak: float = c["LUNGE_PEAK"]
	var total: float = c["LUNGE_TOTAL_S"]
	if absf(w - 0.1) > 0.001:
		_fail("crouch %.2f s, want 0.1" % w)
	var early: float = M.call("lunge_speed", w + 0.04)
	if early < 0.7 * peak:
		_fail("%.1f m/s 0.04 s into the spring (peak %.0f): not front-loaded" % [early, peak])
	var dt := 1.0 / 60.0
	var t := 0.0
	var dist := 0.0
	var neg := 0.0
	var stopped_at := -1.0
	while t < total:
		var v: float = M.call("lunge_speed", t)
		dist += v * dt
		if v < 0.0:
			neg += -v * dt
		if stopped_at < 0.0 and t > w + 0.5 and v <= 0.0:
			stopped_at = t
		t += dt
	if neg < 0.05 or neg > 0.5:
		_fail("rocks back %.2f m after the plant (want a slight overshoot, 0.05-0.5 m)" % neg)
	if dist < 14.0 or dist > 18.0:
		_fail("reach %.1f m (want ~16 m as before)" % dist)
	if float(M.call("lunge_speed", total - 0.001)) < -0.2:
		_fail("still moving back at the end (%.2f m/s): no settle" % float(M.call("lunge_speed", total - 0.001)))
	# an impact: no rock-back, it settles in place
	var mech: Node = load("res://scenes/mech/Mech.tscn").instantiate()
	add_child(mech)
	if not mech.has_method("_lunge_impact"):
		_fail("no impact settle (a ram ends the lunge outright)")
	else:
		mech.call("_lunge_begin", Vector3.FORWARD, w + 0.5)
		mech.call("_lunge_impact")
		var moved := 0.0
		for k in 30:
			mech.call("_lunge_step", dt)
			moved += Vector2(mech.velocity.x, mech.velocity.z).length() * dt
		if moved > 0.001:
			_fail("after an impact it still moves %.2f m (want: settle in place)" % moved)
	print("[probe] lunge_v2 done (reach %.1f m, rock-back %.2f m)" % [dist, neg])
	get_tree().quit(0)
