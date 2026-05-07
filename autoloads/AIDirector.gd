extends Node
# Lightweight bot-coordination singleton.
#
# Each bot registers its current beacon intent so teammates can see how many
# allies are already heading to each beacon and avoid piling on the same one.
#
# Usage (from AIInputSource):
#   AIDirector.set_intent(bot_node, beacon_node, team_id)
#   AIDirector.clear_intent(bot_node)
#   AIDirector.intent_count(beacon_node, team_id) -> int

# Keyed by bot Node reference; value is {beacon: Node, team: int}.
var _intents: Dictionary = {}

func set_intent(bot: Node, beacon: Node, team: int) -> void:
	_intents[bot] = {"beacon": beacon, "team": team}

func clear_intent(bot: Node) -> void:
	_intents.erase(bot)

# Returns how many bots on `team` are currently intending to go to `beacon`.
func intent_count(beacon: Node, team: int) -> int:
	var count := 0
	var stale: Array = []
	for bot in _intents:
		if not is_instance_valid(bot):
			stale.append(bot)
			continue
		var entry: Dictionary = _intents[bot]
		if entry.get("beacon") == beacon and entry.get("team") == team:
			count += 1
	for bot in stale:
		_intents.erase(bot)
	return count
