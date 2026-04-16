extends Node
# Singleton — cross-match persistent state. The only autoload.
#
# Data ownership:
#   profile  — server-owned fields (wins/losses/pilot_name). Keep clean for future sync.
#   loadout  — server-owned fields (chosen mech, weapon config). Same rule.
#   settings — local-only fields (mouse sensitivity). Never sent to server.

var profile: Dictionary = {
	"pilot_name": "Pilot",
	"wins": 0,
	"losses": 0,
}

# Loadout is set in Hangar and consumed by Arena.
# mech_def is a MechDef resource; null until Hangar initialises it.
var loadout: Dictionary = {
	"mech_def": null,
}

var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
}
