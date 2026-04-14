extends Node
# Singleton — cross-match persistent state. The only autoload.

var profile: Dictionary = {
	"pilot_name": "Pilot",
	"wins": 0,
	"losses": 0,
}

var settings: Dictionary = {
	"mouse_sensitivity": 0.003,
}
