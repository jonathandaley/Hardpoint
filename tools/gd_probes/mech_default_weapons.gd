extends Node
# T560 probe (chaos_21): every mech's DEFAULT weapons are catalog weapons of their slot's size. Kestrel's
# second slot defaulted to ProjectileGun.tscn, the April prototype (a grey box, not in WEAPON_CATALOG): the
# hangar can only show catalog weapons, so it showed RIFLE LIGHT there, but a squad slot whose rows were
# never cycled spawns with the mech's defaults -- the player got the prototype gun it never saw.

func _ready() -> void:
	var catalog := {}  # path -> slot_size
	for c in preload("res://scripts/Lobby.gd").WEAPON_CATALOG:
		catalog[c["path"]] = int(c["slot_size"])
	var bad: Array = []
	var n := 0
	for f in DirAccess.get_files_at("res://resources/mechs"):
		if not f.ends_with(".tres"):
			continue
		var md = load("res://resources/mechs/" + f)
		if md == null or not "weapon_slots" in md:
			continue
		n += 1
		for i in md.weapon_slots.size():
			var slot = md.weapon_slots[i]
			var path: String = slot.weapon_scene.resource_path if slot.weapon_scene != null else ""
			var size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0
			if not catalog.has(path):
				bad.append("%s slot %d: %s is not in WEAPON_CATALOG" % [f, i, path])
			elif catalog[path] != size:
				bad.append("%s slot %d: %s is size %d, the slot %d" % [f, i, path, catalog[path], size])
	if n == 0:
		bad.append("no mech defs found")
	if not bad.is_empty():
		push_error("[probe] mech_default_weapons FAIL: " + "; ".join(bad))
	print("[probe] mech_default_weapons done (%d mechs)" % n)
	get_tree().quit(0)
