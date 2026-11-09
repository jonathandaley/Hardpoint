extends Node3D
# T264 (HUMAN_FOUND 2026-11-05: drops from destroyed bots; user: coins by bot difficulty +
# powerups repair / ammo / damage boost / speed boost): one pickup, the same on every peer.
# Arena spawns and removes it by id (server-authoritative); this node is only its look.
# T351 (user on T264: "Make an animation for pickups, wire in a sound (I don't have it yet), make
# the powerup icons more informative, and make them last longer on the ground"): each kind has
# its own shape -- a cross (repair), rounds (ammo), a spike (damage), chevrons (speed) -- under a
# label saying what it does, and collect() plays a short pop instead of vanishing.

const COLORS := {
	"coin":   Color(1.0, 0.82, 0.2),
	"repair": Color(0.3, 1.0, 0.45),
	"ammo":   Color(1.0, 0.6, 0.15),
	"damage": Color(1.0, 0.25, 0.2),
	"speed":  Color(0.3, 0.7, 1.0),
}
const LABELS := {"repair": "+35% HP", "ammo": "AMMO", "damage": "DAMAGE x1.5", "speed": "SPEED x1.3"}
const POP_S := 0.35

var kind := "coin"
var value := 0
var age := 0.0
var collected := false
var _body: Node3D = null
var _mat: StandardMaterial3D = null

func setup(k: String, v: int) -> void:
	kind = k
	value = v

func _box(size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.position = pos
	mi.rotation = rot
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)

func _ready() -> void:
	add_to_group("pickups")  # T352: bots look for them
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = COLORS.get(kind, Color.WHITE)
	_body = Node3D.new()
	add_child(_body)
	match kind:
		"coin":
			var mi := MeshInstance3D.new()
			var c := CylinderMesh.new()
			c.top_radius = 0.32
			c.bottom_radius = 0.32
			c.height = 0.08
			mi.mesh = c
			mi.rotation.x = PI * 0.5  # stands on its edge, spins about y
			mi.material_override = _mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_body.add_child(mi)
		"repair":  # a cross
			_box(Vector3(0.7, 0.22, 0.22), Vector3.ZERO)
			_box(Vector3(0.22, 0.7, 0.22), Vector3.ZERO)
		"ammo":  # three rounds standing up
			for i in 3:
				_box(Vector3(0.14, 0.5, 0.14), Vector3((i - 1) * 0.2, 0, 0))
				_box(Vector3(0.1, 0.12, 0.1), Vector3((i - 1) * 0.2, 0.31, 0), Vector3(0, PI * 0.25, 0))
		"damage":  # a spike pointing up
			_box(Vector3(0.36, 0.36, 0.36), Vector3(0, -0.05, 0), Vector3(PI * 0.25, 0, PI * 0.25))
			_box(Vector3(0.12, 0.45, 0.12), Vector3(0, 0.3, 0))
		"speed":  # two chevrons
			for i in 2:
				_box(Vector3(0.42, 0.1, 0.12), Vector3(-0.14, 0.15 - i * 0.28, 0), Vector3(0, 0, 0.6))  # "^"
				_box(Vector3(0.42, 0.1, 0.12), Vector3(0.14, 0.15 - i * 0.28, 0), Vector3(0, 0, -0.6))
	if LABELS.has(kind):
		var lbl := Label3D.new()
		lbl.text = LABELS[kind]
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 40
		lbl.pixel_size = 0.006
		lbl.outline_size = 8
		lbl.modulate = COLORS[kind]
		lbl.position.y = 0.75
		_body.add_child(lbl)

func _process(delta: float) -> void:
	age += delta
	if collected:
		return
	_body.rotation.y += delta * 2.5
	_body.position.y = 0.7 + sin(age * 3.0) * 0.12

## The pickup was taken: a quick pop (rise, swell, fade), then gone.
func collect() -> void:
	if collected:
		return
	collected = true
	var tw := create_tween().set_parallel()
	tw.tween_property(_body, "position:y", _body.position.y + 1.2, POP_S)
	tw.tween_property(_body, "scale", Vector3.ONE * 1.8, POP_S)
	tw.tween_property(_mat, "albedo_color:a", 0.0, POP_S)
	for l in _body.find_children("*", "Label3D", false, false):
		tw.tween_property(l, "modulate:a", 0.0, POP_S)
	tw.chain().tween_callback(queue_free)
