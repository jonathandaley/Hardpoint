extends Node
# T311 + T313 probe (user 2026-11-05: Patience "remove the screen jiggle on firing; this one
# should be smooth"; "Reduce sniper recoil/screen shudder by 50%"): Patience shakes the camera
# not at all; each sniper shakes half what it did (light 0.02 -> 0.01, heavy 0.025 -> 0.0125).

const WANT := {"PatienceHeavy": 0.0, "SniperLight": 0.01, "SniperHeavy": 0.0125}

func _ready() -> void:
	var bad := false
	for n in WANT:
		var w: Node = (load("res://scenes/weapons/%s.tscn" % n) as PackedScene).instantiate()
		var got: float = w.get("shake_magnitude")
		w.free()
		if absf(got - WANT[n]) > 0.0001:
			push_error("[probe] weapon_feel FAIL: %s shake %.4f, want %.4f" % [n, got, WANT[n]])
			bad = true
	if bad:
		get_tree().quit(1)
		return
	print("[probe] weapon_feel done")
	get_tree().quit(0)
