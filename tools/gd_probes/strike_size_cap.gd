extends Node
# T381 probe (HUMAN_FOUND 2026-11-09: aerial strike "too big on Seeker"): the strike pod's model stops
# growing at WeaponVisuals.MULT_CAP (Seeker's weapon_scale 2.0 draws it at the cap), while other
# weapons still take the full multiplier (T191's big guns on Seeker stay).
const WV := preload("res://scripts/WeaponVisuals.gd")

func _size(scene: String, mult: float) -> Vector3:
	var w: Node3D = load(scene).instantiate()
	add_child(w)
	WV.apply(w, mult)
	var box := AABB()
	for c in w.get_children():
		if c is MeshInstance3D:
			box = box.merge((c as MeshInstance3D).get_aabb()) if box.size != Vector3.ZERO else (c as MeshInstance3D).get_aabb()
	w.queue_free()
	return box.size

func _ready() -> void:
	var cap: float = (load("res://scripts/WeaponVisuals.gd") as Script).get_script_constant_map().get("MULT_CAP", {}).get("AerialStrike", 99.0)  # (red runs on code without it)
	var big := _size("res://scenes/weapons/AerialStrikeHeavy.tscn", 2.0)
	var capped := _size("res://scenes/weapons/AerialStrikeHeavy.tscn", minf(cap, 1.2))
	if big.is_zero_approx() or not big.is_equal_approx(capped):
		push_error("[probe] strike_size_cap: strike pod at x2.0 is %s, at the cap %s (want equal)" % [big, capped])
	var rifle2 := _size("res://scenes/weapons/RifleHeavy.tscn", 2.0)
	var rifle1 := _size("res://scenes/weapons/RifleHeavy.tscn", 1.2)
	if rifle2.x <= rifle1.x * 1.5 and rifle2.z <= rifle1.z * 1.5:
		push_error("[probe] strike_size_cap: the rifle stopped growing too (%s vs %s)" % [rifle2, rifle1])
	print("[probe] strike_size_cap done")
	get_tree().quit(0)
