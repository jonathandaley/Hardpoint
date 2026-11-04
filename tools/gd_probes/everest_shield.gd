extends Node
# T218 probe (HUMAN_FOUND_ISSUES: "Everest sometimes shows the old blue shield under the
# current textured one -- before taking damage?"): a spawned Everest's physical shield is
# up (collides), but its pre-kit placeholder mesh draws nothing; the kit model is the look.

func _fail(msg: String) -> void:
	push_error("[probe] everest_shield: " + msg)

func _ready() -> void:
	Game.mp_active_match["roster"] = []
	Game.loadout["team_size"] = 1
	Game.loadout["squad"] = ["res://resources/mechs/Everest.tres"]
	var arena: Node = load("res://scenes/arena/Arena.tscn").instantiate()
	get_tree().root.add_child.call_deferred(arena)
	for i in 2:
		await get_tree().process_frame
	if arena.get("_start_pick_open"):
		arena.get("hud").squad_slot_selected.emit(0)
		arena.get("hud").spawn_selected.emit(0)
	for i in 10:
		await get_tree().physics_frame
	var m: Node = arena.get("player_mech")
	var shield: Node3D = m.get_node("Torso/PhysicalShield")
	if not shield.visible or (shield.get_node("CollisionShape3D") as CollisionShape3D).disabled:
		_fail("Everest's physical shield is not up at spawn")
	var old := shield.get_node_or_null("ShieldMesh") as MeshInstance3D
	if old != null and old.mesh != null and old.is_visible_in_tree():
		_fail("the old blue placeholder shield still draws under the kit model")
	print("[probe] everest_shield done")
	get_tree().quit(0)
