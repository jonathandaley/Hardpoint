extends "res://tools/gd_probes/map_stuck.gd"
# T230: the map_stuck walk-out with the biggest roster mech (Everest / Vesuvius, 1.25 scale):
# a gap a Hippogriff passes can still pin a big one. Own probe: two mechs in one would not
# fit the suite's 6000-frame probe cap.

func _init() -> void:
	mech_path = "res://resources/mechs/Everest.tres"
