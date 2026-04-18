extends Control

const ROSTER: Array = [
	"res://resources/mechs/Lynx.tres",
	"res://resources/mechs/Hippogriff.tres",
	"res://resources/mechs/Kestrel.tres",
	"res://resources/mechs/Warhog.tres",
]

const WEAPON_CATALOG: Array = [
	{"name": "RIFLE LIGHT",    "path": "res://scenes/weapons/RifleLight.tscn",    "slot_size": 0},
	{"name": "SNIPER LIGHT",   "path": "res://scenes/weapons/SniperLight.tscn",   "slot_size": 0},
	{"name": "PROJECTILE GUN", "path": "res://scenes/weapons/ProjectileGun.tscn", "slot_size": 0},
	{"name": "RIFLE HEAVY",    "path": "res://scenes/weapons/RifleHeavy.tscn",    "slot_size": 1},
	{"name": "SNIPER HEAVY",   "path": "res://scenes/weapons/SniperHeavy.tscn",   "slot_size": 1},
]

@onready var mech_panel: Control = $Content/MechPanel
@onready var pilot_panel: Control = $Content/PilotPanel
@onready var pilot_label: Label = $TopBar/PilotLabel
@onready var pilot_name_label: Label = $Content/PilotPanel/PilotName
@onready var pilot_record_label: Label = $Content/PilotPanel/PilotRecord
@onready var mech_name_label: Label = $Content/MechPanel/MechName
@onready var mech_stats_label: Label = $Content/MechPanel/MechStats
@onready var weapon_slot_label: Label = $Content/MechPanel/WeaponSlot
@onready var roster_list: VBoxContainer = $Content/MechPanel/RosterPanel/RosterList

var _mechs: Array = []
var _selected: int = 0
var _weapon_indices: Array = []      # WEAPON_CATALOG index per slot for the selected mech
var _weapon_name_labels: Array = []  # Label refs in the picker, updated in-place on cycle

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	weapon_slot_label.visible = false
	var pilot_name: String = Game.profile.get("pilot_name", "Pilot")
	pilot_label.text = pilot_name
	pilot_name_label.text = "NAME: " + pilot_name.to_upper()
	var wins: int = Game.profile.get("wins", 0)
	var losses: int = Game.profile.get("losses", 0)
	pilot_record_label.text = "WINS: %d   LOSSES: %d" % [wins, losses]
	_load_roster()
	_ensure_default_mech()
	_build_roster_buttons()
	_update_mech_panel()
	_show_tab(0)

func _load_roster() -> void:
	_mechs.clear()
	for path in ROSTER:
		var md = load(path)
		if md != null:
			_mechs.append(md)
		else:
			push_error("[Hangar] Failed to load MechDef: " + path)

func _ensure_default_mech() -> void:
	var current = Game.loadout.get("mech_def")
	if current == null:
		_selected = 1 if _mechs.size() > 1 else 0
		if _mechs.size() > 0:
			Game.loadout.mech_def = _mechs[_selected]
	else:
		for i in _mechs.size():
			if _mechs[i] == current:
				_selected = i
				_init_weapon_overrides()
				return
		_selected = 0
		if _mechs.size() > 0:
			Game.loadout.mech_def = _mechs[0]
	_init_weapon_overrides()

func _init_weapon_overrides() -> void:
	var md = Game.loadout.get("mech_def")
	if md == null:
		return
	var slots: Array = md.weapon_slots
	_weapon_indices.resize(slots.size())
	var saved: Array = Game.loadout.get("mech_weapon_choices", {}).get(md.resource_path, [])
	var overrides: Array = []
	for i in slots.size():
		var slot = slots[i]
		var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0
		var target_path: String = saved[i] if i < saved.size() else ""
		if target_path == "":
			target_path = slot.weapon_scene.resource_path if slot.weapon_scene != null else ""
		var found: int = -1
		for j in WEAPON_CATALOG.size():
			if WEAPON_CATALOG[j]["slot_size"] == s_size:
				if found < 0:
					found = j
				if WEAPON_CATALOG[j]["path"] == target_path:
					found = j
					break
		_weapon_indices[i] = found if found >= 0 else 0
		var scene: PackedScene = load(WEAPON_CATALOG[_weapon_indices[i]]["path"])
		overrides.append(scene)
	Game.loadout["weapon_overrides"] = overrides

func _build_roster_buttons() -> void:
	for child in roster_list.get_children():
		child.queue_free()
	for i in _mechs.size():
		var md = _mechs[i]
		var btn := Button.new()
		btn.text = "%s\n%s" % [md.display_name.to_upper(), md.class_tag.to_upper()]
		btn.custom_minimum_size = Vector2(160, 44)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_roster_selected.bind(i))
		roster_list.add_child(btn)
	_highlight_selected()

func _highlight_selected() -> void:
	var buttons := roster_list.get_children()
	for i in buttons.size():
		var btn: Button = buttons[i]
		if i == _selected:
			btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
		else:
			btn.remove_theme_color_override("font_color")

func _on_roster_selected(idx: int) -> void:
	_selected = idx
	Game.loadout.mech_def = _mechs[idx]
	_init_weapon_overrides()
	Game.save_loadout()
	_highlight_selected()
	_update_mech_panel()

func _update_mech_panel() -> void:
	var md = Game.loadout.get("mech_def")
	if md == null:
		return
	mech_name_label.text = "MECH: %s (%s)" % [md.display_name.to_upper(), md.class_tag.to_upper()]
	var shield_str := "YES" if md.has_shields else "-"
	mech_stats_label.text = "SPEED: %.2f   HEALTH: %.0f   SHIELDS: %s" % [md.walk_speed, md.max_health, shield_str]
	_build_weapon_picker(md)

func _build_weapon_picker(md) -> void:
	var existing := mech_panel.get_node_or_null("WeaponPicker")
	if existing:
		existing.free()

	var slots: Array = md.weapon_slots
	var row_h := 24.0
	var picker_top := 44.0

	_weapon_name_labels.clear()

	var picker := VBoxContainer.new()
	picker.name = "WeaponPicker"
	picker.offset_left = 200.0
	picker.offset_top = picker_top
	picker.offset_right = 630.0
	picker.offset_bottom = picker_top + slots.size() * row_h
	picker.add_theme_constant_override("separation", 2)
	mech_panel.add_child(picker)

	for i in slots.size():
		var slot = slots[i]
		var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0
		var size_str: String = "HEAVY" if s_size == 1 else "LIGHT"

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, row_h - 2.0)
		row.add_theme_constant_override("separation", 4)
		picker.add_child(row)

		var slot_lbl := Label.new()
		slot_lbl.text = "S%d [%s]" % [i + 1, size_str]
		slot_lbl.add_theme_font_size_override("font_size", 13)
		slot_lbl.custom_minimum_size = Vector2(90, 0)
		slot_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(slot_lbl)

		var prev_btn := Button.new()
		prev_btn.text = "<"
		prev_btn.custom_minimum_size = Vector2(22, 0)
		prev_btn.add_theme_font_size_override("font_size", 13)
		prev_btn.pressed.connect(_on_weapon_cycle.bind(i, -1))
		row.add_child(prev_btn)

		var cat_idx: int = _weapon_indices[i] if i < _weapon_indices.size() else 0
		var wep_name: String = WEAPON_CATALOG[cat_idx]["name"] if cat_idx >= 0 else "NONE"

		var wep_lbl := Label.new()
		wep_lbl.text = wep_name
		wep_lbl.add_theme_font_size_override("font_size", 13)
		wep_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wep_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(wep_lbl)
		_weapon_name_labels.append(wep_lbl)

		var next_btn := Button.new()
		next_btn.text = ">"
		next_btn.custom_minimum_size = Vector2(22, 0)
		next_btn.add_theme_font_size_override("font_size", 13)
		next_btn.pressed.connect(_on_weapon_cycle.bind(i, 1))
		row.add_child(next_btn)

	var stats_top: float = picker_top + slots.size() * row_h + 8.0
	mech_stats_label.offset_top = stats_top
	mech_stats_label.offset_bottom = stats_top + 28.0

func _on_weapon_cycle(slot_idx: int, direction: int) -> void:
	var md = Game.loadout.get("mech_def")
	if md == null or slot_idx >= md.weapon_slots.size():
		return
	var slot = md.weapon_slots[slot_idx]
	var s_size: int = int(slot.get("slot_size")) if "slot_size" in slot else 0

	var compatible: Array = []
	for i in WEAPON_CATALOG.size():
		if WEAPON_CATALOG[i]["slot_size"] == s_size:
			compatible.append(i)
	if compatible.is_empty():
		return

	var cur: int = _weapon_indices[slot_idx] if slot_idx < _weapon_indices.size() else compatible[0]
	var pos: int = compatible.find(cur)
	if pos < 0:
		pos = 0
	pos = (pos + direction + compatible.size()) % compatible.size()
	_weapon_indices[slot_idx] = compatible[pos]

	var overrides: Array = Game.loadout.get("weapon_overrides", [])
	while overrides.size() <= slot_idx:
		overrides.append(null)
	overrides[slot_idx] = load(WEAPON_CATALOG[_weapon_indices[slot_idx]]["path"])
	Game.loadout["weapon_overrides"] = overrides

	if md != null:
		var choices: Dictionary = Game.loadout.get("mech_weapon_choices", {})
		var paths: Array = []
		for o in overrides:
			paths.append(o.resource_path if o != null else "")
		choices[md.resource_path] = paths
		Game.loadout["mech_weapon_choices"] = choices
		Game.save_loadout()

	if slot_idx < _weapon_name_labels.size() and is_instance_valid(_weapon_name_labels[slot_idx]):
		_weapon_name_labels[slot_idx].text = WEAPON_CATALOG[_weapon_indices[slot_idx]]["name"]

func _show_tab(idx: int) -> void:
	mech_panel.visible = idx == 0
	pilot_panel.visible = idx == 1

func _on_mech_tab_pressed() -> void:
	_show_tab(0)

func _on_pilot_tab_pressed() -> void:
	_show_tab(1)

func _on_matchmaking_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/arena/Arena.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/Settings.tscn")
