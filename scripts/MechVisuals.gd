class_name MechVisuals

# Apply per-mech body geometry. Call after instantiate() but before add_child()
# so accessories are present when Mech._ready() builds _body_meshes.
static func apply(mech: Node3D, display_name: String) -> void:
	match display_name:
		"Slip":       _slip(mech)
		"Cesh":       _cesh(mech)
		"Seeker":     _seeker(mech)
		"Lynx":       _lynx(mech)
		"Hornet":     _hornet(mech)
		"Hippogriff": _hippogriff(mech)
		"Kestrel":    _kestrel(mech)
		"Pegasus":    _pegasus(mech)
		"Everest":    _everest(mech)
		"Vesuvius":   _vesuvius(mech)
		"Warhog":     _warhog(mech)


# ---- mesh setters ----

static func _bm(mi: MeshInstance3D, sz: Vector3) -> void:
	if mi == null:
		return
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m

static func _cyl(mi: MeshInstance3D, tr: float, br: float, h: float, segs: int = 16) -> void:
	if mi == null:
		return
	var m := CylinderMesh.new()
	m.top_radius = tr
	m.bottom_radius = br
	m.height = h
	m.radial_segments = segs
	mi.mesh = m

static func _sph(mi: MeshInstance3D, r: float) -> void:
	if mi == null:
		return
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	mi.mesh = m


# ---- accessory factories (added as Torso or Legs children) ----

static func _add_box(parent: Node3D, pos: Vector3, sz: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = sz
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi

static func _add_cyl(parent: Node3D, pos: Vector3, tr: float, br: float, h: float, segs: int = 12) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = tr
	m.bottom_radius = br
	m.height = h
	m.radial_segments = segs
	mi.mesh = m
	mi.position = pos
	parent.add_child(mi)
	return mi


# ---- leg segment helpers ----

static func _leg_segs(l: Node3D, upper: Vector3, mid: Vector3, lower: Vector3) -> void:
	_bm(l.get_node_or_null("LeftHip/UpperLeft") as MeshInstance3D,                         upper)
	_bm(l.get_node_or_null("RightHip/UpperRight") as MeshInstance3D,                       upper)
	_bm(l.get_node_or_null("LeftHip/LeftKnee1/MidLeft") as MeshInstance3D,                 mid)
	_bm(l.get_node_or_null("RightHip/RightKnee1/MidRight") as MeshInstance3D,              mid)
	_bm(l.get_node_or_null("LeftHip/LeftKnee1/LeftKnee2/LowerLeft") as MeshInstance3D,     lower)
	_bm(l.get_node_or_null("RightHip/RightKnee1/RightKnee2/LowerRight") as MeshInstance3D, lower)

# Light class: long thin sprinter legs, blade feet
static func _light_legs(l: Node3D) -> void:
	_leg_segs(l, Vector3(0.18, 0.60, 0.17), Vector3(0.16, 0.60, 0.15), Vector3(0.14, 0.18, 0.32))

# Heavy class: thick pillar legs
static func _heavy_legs(l: Node3D) -> void:
	_leg_segs(l, Vector3(0.28, 0.55, 0.26), Vector3(0.26, 0.55, 0.24), Vector3(0.24, 0.55, 0.22))


# ==== per-mech designs ====
# All positions are in Torso-space (Torso node is at mech root, no offset).
# Mech faces -Z. +Z is back. +X is left when facing mech from front.
# Key Torso-space landmarks (default): Waist Y=1.02, Body Y=1.42, Shoulders Y=1.72 +/-0.68X, Head Y=1.92


# Slip: aerodynamic sprinter -- narrow side profile, blade feet, dorsal fin, visor
static func _slip(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,          Vector3(0.72, 0.55, 0.85))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D,         Vector3(0.52, 0.14, 0.60))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,          Vector3(0.36, 0.20, 0.44))
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.15, 0.16, 0.48))
		_bm(sr, Vector3(0.15, 0.16, 0.48))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		_add_box(t, Vector3(0.0, 1.92, -0.26), Vector3(0.28, 0.05, 0.04))  # visor slit
		_add_box(t, Vector3(0.0, 1.70, 0.46),  Vector3(0.05, 0.22, 0.14))  # dorsal fin
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.78, 0.18, 0.44))
		_leg_segs(l,
			Vector3(0.17, 0.62, 0.16),
			Vector3(0.15, 0.62, 0.14),
			Vector3(0.13, 0.16, 0.34))  # blade foot: wide Z, short Y


# Cesh: hunched stealth predator -- wide low body, sensor pod on shoulder
static func _cesh(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,          Vector3(1.04, 0.50, 0.76))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D,         Vector3(0.62, 0.12, 0.60))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,          Vector3(0.38, 0.18, 0.44))
		_bm(t.get_node_or_null("ShoulderLeft") as MeshInstance3D,  Vector3(0.24, 0.20, 0.58))
		_bm(t.get_node_or_null("ShoulderRight") as MeshInstance3D, Vector3(0.24, 0.20, 0.58))
		_add_cyl(t, Vector3(-0.68, 1.84, 0.0), 0.08, 0.08, 0.18, 8)  # sensor pod atop left shoulder
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.96, 0.20, 0.54))
		_leg_segs(l,
			Vector3(0.18, 0.56, 0.17),
			Vector3(0.16, 0.50, 0.15),  # shorter lower limbs = crouched stance
			Vector3(0.14, 0.50, 0.14))


# Seeker: dense sensor-ball head, asymmetric heavy weapon shoulder
static func _seeker(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(0.90, 0.60, 0.72))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.68, 0.18, 0.62))
		_sph(t.get_node_or_null("Head") as MeshInstance3D, 0.22)  # sensor orb
		_bm(t.get_node_or_null("ShoulderLeft") as MeshInstance3D,  Vector3(0.18, 0.20, 0.44))
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sr, Vector3(0.32, 0.36, 0.62))  # oversized heavy hardpoint mount
		if sr: sr.position.x = 0.72
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.84, 0.20, 0.50))
		_leg_segs(l,
			Vector3(0.22, 0.50, 0.20),  # stocky legs
			Vector3(0.20, 0.50, 0.18),
			Vector3(0.18, 0.50, 0.16))


# Lynx: lithe cat silhouette -- tapered cylinder torso, long legs, antenna spike
static func _lynx(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_cyl(t.get_node_or_null("Body") as MeshInstance3D, 0.30, 0.38, 0.58)  # tapered cylinder
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.56, 0.14, 0.56))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,  Vector3(0.32, 0.26, 0.46))  # angular wedge
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.16, 0.18, 0.50))
		_bm(sr, Vector3(0.16, 0.18, 0.50))
		if sl: sl.position.x = -0.52
		if sr: sr.position.x =  0.52
		_add_box(t, Vector3(0.0, 2.10, 0.0), Vector3(0.04, 0.20, 0.04))  # antenna spike
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(0.80, 0.18, 0.46))
		_leg_segs(l,
			Vector3(0.17, 0.64, 0.16),  # longest legs in the roster
			Vector3(0.15, 0.64, 0.14),
			Vector3(0.13, 0.20, 0.28))


# Hornet: F-18 jet -- wide flat fuselage, tall cockpit canopy, swept pylons, engine nacelles
static func _hornet(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.12, 0.48, 0.82))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.58, 0.16, 0.68))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,  Vector3(0.38, 0.40, 0.50))  # tall cockpit canopy
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.38, 0.16, 0.72))  # wide swept wing pylons
		_bm(sr, Vector3(0.38, 0.16, 0.72))
		if sl: sl.position.x = -0.80
		if sr: sr.position.x =  0.80
		# twin engine nacelles lower back
		_add_cyl(t, Vector3(-0.22, 1.20, 0.46), 0.10, 0.12, 0.40, 10)
		_add_cyl(t, Vector3( 0.22, 1.20, 0.46), 0.10, 0.12, 0.40, 10)
	# legs: standard medium, no change


# Hippogriff: B-29 bomber -- round fuselage, nose dome, wide wing sponsons
static func _hippogriff(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_cyl(t.get_node_or_null("Body") as MeshInstance3D, 0.46, 0.52, 0.64)  # round bomber fuselage
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.76, 0.22, 0.68))
		_sph(t.get_node_or_null("Head") as MeshInstance3D, 0.24)  # B-29 nose dome
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.42, 0.15, 0.74))  # flat wing sponsons
		_bm(sr, Vector3(0.42, 0.15, 0.74))
		if sl: sl.position.x = -0.80
		if sr: sr.position.x =  0.80
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.08, 0.24, 0.60))
		_leg_segs(l,
			Vector3(0.26, 0.52, 0.24),  # wide bomber stance
			Vector3(0.24, 0.52, 0.22),
			Vector3(0.22, 0.52, 0.20))


# Kestrel: energy shield tech -- hexagonal prism body, octagonal sensor head, shield emitter cross
static func _kestrel(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		_cyl(t.get_node_or_null("Body") as MeshInstance3D,  0.40, 0.46, 0.62, 6)   # hexagonal prism
		_bm(t.get_node_or_null("Waist") as MeshInstance3D,  Vector3(0.65, 0.18, 0.58))
		_cyl(t.get_node_or_null("Head") as MeshInstance3D,  0.17, 0.17, 0.28, 8)   # octagonal sensor drum
		_cyl(t.get_node_or_null("ShoulderLeft") as MeshInstance3D,  0.18, 0.20, 0.22, 6)  # hex caps
		_cyl(t.get_node_or_null("ShoulderRight") as MeshInstance3D, 0.18, 0.20, 0.22, 6)
		# shield emitter projectors: cross-shaped band at waist
		_add_box(t, Vector3(0.0, 1.02, 0.0), Vector3(1.10, 0.06, 0.04))
		_add_box(t, Vector3(0.0, 1.02, 0.0), Vector3(0.04, 0.06, 1.10))
	# legs: standard medium, no change


# Pegasus: angelic mobility mech -- slim body, raised wing shoulders, jump jet pack, head crest
static func _pegasus(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(0.86, 0.60, 0.72))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.58, 0.16, 0.60))
		_bm(t.get_node_or_null("Head") as MeshInstance3D,  Vector3(0.36, 0.34, 0.42))
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.22, 0.20, 0.58))  # swept wing-like
		_bm(sr, Vector3(0.22, 0.20, 0.58))
		if sl: sl.position.y = 1.82  # raised higher than default 1.72
		if sr: sr.position.y = 1.82
		# jump jets: twin cylinders on lower back
		_add_cyl(t, Vector3(-0.18, 1.32, 0.44), 0.10, 0.12, 0.48, 10)
		_add_cyl(t, Vector3( 0.18, 1.32, 0.44), 0.10, 0.12, 0.48, 10)
		# head crest
		_add_box(t, Vector3(0.0, 2.08, 0.0), Vector3(0.06, 0.18, 0.04))
	# legs: standard medium, no change


# Everest: fortress paladin -- massive box, huge pauldrons, pillar legs, chest cross emblem
static func _everest(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.10, 0.75, 0.86))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.80, 0.24, 0.76))
		var head := t.get_node_or_null("Head") as MeshInstance3D
		_bm(head, Vector3(0.45, 0.44, 0.46))  # cube knight helm
		if head: head.position.y = 2.00  # shifted up to clear taller body
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.38, 0.36, 0.72))  # massive pauldrons
		_bm(sr, Vector3(0.38, 0.36, 0.72))
		if sl: sl.position = Vector3(-0.82, 1.82, 0.0)
		if sr: sr.position = Vector3( 0.82, 1.82, 0.0)
		# chest cross emblem -- horizontal and vertical bars on front face
		_add_box(t, Vector3(0.0, 1.52, -0.44), Vector3(0.44, 0.08, 0.04))
		_add_box(t, Vector3(0.0, 1.52, -0.44), Vector3(0.08, 0.34, 0.04))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.16, 0.28, 0.66))
		_heavy_legs(l)


# Vesuvius: volcano dreadnought -- broad weapon platform, tapered volcanic head, exhaust stacks
static func _vesuvius(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.18, 0.70, 0.88))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.82, 0.24, 0.76))
		_cyl(t.get_node_or_null("Head") as MeshInstance3D, 0.18, 0.30, 0.34, 12)  # wide at base like a crater
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.42, 0.40, 0.74))  # massive weapon mounts
		_bm(sr, Vector3(0.42, 0.40, 0.74))
		if sl: sl.position.x = -0.84
		if sr: sr.position.x =  0.84
		# exhaust stacks on back: three chimneys at different heights
		_add_cyl(t, Vector3(-0.26, 1.60, 0.48), 0.06, 0.06, 0.44, 8)
		_add_cyl(t, Vector3( 0.00, 1.66, 0.48), 0.06, 0.06, 0.56, 8)
		_add_cyl(t, Vector3( 0.26, 1.60, 0.48), 0.06, 0.06, 0.44, 8)
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.14, 0.28, 0.66))
		_heavy_legs(l)


# Warhog: brutish boar tank -- squat wide body, forward snout head, tusks, heavy shoulders
static func _warhog(mech: Node3D) -> void:
	var t := mech.get_node_or_null("Torso") as Node3D
	var l := mech.get_node_or_null("Legs") as Node3D
	if t:
		_bm(t.get_node_or_null("Body") as MeshInstance3D,  Vector3(1.12, 0.64, 0.88))
		_bm(t.get_node_or_null("Waist") as MeshInstance3D, Vector3(0.84, 0.22, 0.76))
		var head := t.get_node_or_null("Head") as MeshInstance3D
		_bm(head, Vector3(0.44, 0.28, 0.58))  # wide snout
		if head:
			head.position.y = 1.82   # lowered
			head.position.z = -0.08  # jutting forward
		var sl := t.get_node_or_null("ShoulderLeft") as MeshInstance3D
		var sr := t.get_node_or_null("ShoulderRight") as MeshInstance3D
		_bm(sl, Vector3(0.36, 0.32, 0.68))
		_bm(sr, Vector3(0.36, 0.32, 0.68))
		if sl: sl.position.x = -0.78
		if sr: sr.position.x =  0.78
		# tusks -- forward of the snout at chin level
		_add_box(t, Vector3(-0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22))
		_add_box(t, Vector3( 0.14, 1.68, -0.48), Vector3(0.06, 0.05, 0.22))
	if l:
		_bm(l.get_node_or_null("Hips") as MeshInstance3D, Vector3(1.12, 0.26, 0.64))
		_heavy_legs(l)
