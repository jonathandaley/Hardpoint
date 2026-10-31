extends Node
# T146 / B-h probe: a snapshot delivered to a mech that has left the tree (scene
# change window: the old Arena is detached but not yet freed, so RPCs still reach
# it) must be ignored without engine errors. Run as a scene so autoloads exist:
#   godot --headless --path . res://tools/gd_probes/detached_snapshot.tscn
# run_suite.py runs every probe scene and scans its output with crash_scan.

func _ready() -> void:
	var m: Node = load("res://scenes/mech/Mech.tscn").instantiate()
	add_child(m)
	await get_tree().process_frame
	remove_child(m)
	m.receive_snapshot({"pos": Vector3(1, 2, 3), "quat": Quaternion.IDENTITY, "vel": Vector3.ZERO, "torso_y": 0.5})
	m.receive_snapshot({})  # no fields: defaults must not read a detached transform either
	print("[probe] detached_snapshot done")
	m.free()
	get_tree().quit(0)
