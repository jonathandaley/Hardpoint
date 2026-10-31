extends Node
# T160 / B44 probe: ending an MP session must clear lobby peers and the match
# roster, or a later SP match spawns through the MP path (Arena._ready checks
# roster.size() > 0) and a later host inherits stale peers.

func _ready() -> void:
	Game.mp_lobby["peers"][7] = {"pilot_name": "stale"}
	Game.mp_active_match["roster"] = [{"peer_id": 7, "team": 1}]
	Game.disconnect_mp()
	if not Game.mp_lobby["peers"].is_empty() or not (Game.mp_active_match["roster"] as Array).is_empty():
		push_error("[probe] session_reset: stale MP state survived disconnect_mp")
	Game.mp_active_match["roster"] = [{"peer_id": 7, "team": 1}]
	Game._on_mp_server_disconnected()
	if not (Game.mp_active_match["roster"] as Array).is_empty():
		push_error("[probe] session_reset: stale roster survived server loss")
	print("[probe] session_reset done")
	get_tree().quit(0)
