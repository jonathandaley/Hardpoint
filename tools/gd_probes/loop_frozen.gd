extends Node
# T565 probe (T563 net sweep, arc_match_end@bad): at match end Arena.freeze_mechs disables every mech and
# its loop sound pauses -- but RPCs still reach a disabled node, and a late hide + beam from the server's
# last ticks restarted the arc loop, which the frozen weapon never aged out: stuck on through the results.
# Each loop weapon under a disabled parent: starting its loop plays nothing.
const WEAPONS := {
	"res://scenes/weapons/ArcWeaponLight.tscn": "_start_arc_loop",
	"res://scenes/weapons/LaserCannonLight.tscn": "_start_laser_loop",
	"res://scenes/weapons/FlamerLight.tscn": "_start_loop",
	"res://scenes/weapons/MachineGunLight.tscn": "_start_mg_loop",
}

func _ready() -> void:
	var bad: Array = []
	var frozen := Node3D.new()
	frozen.process_mode = Node.PROCESS_MODE_DISABLED  # what freeze_mechs does to a mech
	add_child(frozen)
	for path in WEAPONS:
		var w: Node = (load(path) as PackedScene).instantiate()
		frozen.add_child(w)
		w.call(WEAPONS[path])
		var lp = w.get("_loop_player")
		if lp != null and lp.playing and not lp.stream_paused:
			bad.append("%s: %s on a frozen weapon plays" % [path.get_file(), WEAPONS[path]])
	if not bad.is_empty():
		push_error("[probe] loop_frozen FAIL: " + "; ".join(bad))
		get_tree().quit(1)
		return
	print("[probe] loop_frozen done (%d weapons)" % WEAPONS.size())
	get_tree().quit(0)
