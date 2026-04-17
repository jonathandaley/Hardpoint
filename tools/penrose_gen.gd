#!/usr/bin/env -S godot --headless --script
# Penrose P3 tiling generator (fat + thin rhombuses).
# Run from project root:
#   ~/bin/godot --headless --path /home/jonathan/mechbattle --script tools/penrose_gen.gd
#
# Output (stdout): one line per edge and one line per vertex, tab-separated.
# Use this data to place walls (edge midpoints + angles) and pillars (vertices).
#
# Pentagon orientation: the initial "sun" seed has V0 pointing +z (north),
# matching the beacon pentagon and giving x=0 team symmetry.

extends SceneTree

const PHI := 1.6180339887  # golden ratio

# --- Rhombus types ---
# Fat  (thick): interior angles 72° and 108°, sides both = 1.0
# Thin (acute): interior angles 36° and 144°, sides both = 1.0

# A tile is represented as four vertices in order (v0, v1, v2, v3) where
# v0 and v2 are the "pointy" vertices (acute angles).
# We store tiles as arrays: [type, v0, v1, v2, v3]
# type: "fat" or "thin"

# Deflation (subdivision) rules for P3:
#   Fat  → 2 fat + 1 thin
#   Thin → 1 fat + 1 thin
# We implement inflation instead (build outward from a central sun).

# ---- Vector2 helpers ----
static func v2(x: float, y: float) -> Vector2:
	return Vector2(x, y)

static func polar(angle_rad: float, r: float = 1.0) -> Vector2:
	return Vector2(cos(angle_rad) * r, sin(angle_rad) * r)

# ---- Build initial sun (5 fat rhombuses around origin, V0 pointing +Y = +z in 3D) ----
# In 2D tool space: X maps to arena X, Y maps to arena Z.
# V0 at 90° (pointing up/north) so x=0 axis is the team symmetry axis.
static func make_sun(side: float) -> Array:
	var tiles: Array = []
	for k in range(5):
		# Each fat rhombus: vertex at origin, arms at angles a0 and a1.
		# Start at 90° (pointing +Y), step by 72°.
		var a0 := deg_to_rad(90.0 + k * 72.0)
		var a1 := deg_to_rad(90.0 + (k + 1) * 72.0)
		var v0 := Vector2.ZERO
		var v1 := polar(a0, side)
		var v3 := polar(a1, side)
		var v2 := v1 + v3  # opposite corner
		tiles.append(["fat", v0, v1, v2, v3])
	return tiles

# ---- Deflation: one step of P3 subdivision ----
# Each fat rhombus → [fat(large half), fat(small copy), thin]
# Each thin rhombus → [fat, thin]
# Side length shrinks by 1/PHI each step (so after n steps side = original / PHI^n).
static func deflate(tiles: Array) -> Array:
	var result: Array = []
	for t in tiles:
		var tp: String = t[0]
		var A: Vector2 = t[1]
		var B: Vector2 = t[2]
		var C: Vector2 = t[3]  # opposite to A in fat, or adjacent in thin
		var D: Vector2 = t[4]
		if tp == "fat":
			# Fat rhombus ABCD (A and C are 72° corners, B and D are 108° corners).
			# New point P divides AB such that AP = 1/PHI * AB (the short diagonal).
			var P := A + (B - A) / PHI
			var Q := A + (D - A) / PHI
			result.append(["fat",  C, B, P, A])   # large piece
			result.append(["fat",  C, D, Q, A])   # mirror large piece
			result.append(["thin", P, B, C, Q])   # thin in the middle (recheck winding)
			# Corrected winding so thin has its acute angle at P and Q:
			result[-1] = ["thin", A, P, C, Q]
		else:
			# Thin rhombus ABCD (A and C are 36° corners).
			var P := B + (A - B) / PHI
			result.append(["fat",  P, A, D, C])   # note: recheck winding
			result.append(["thin", P, B, C, D])
			# Corrected:
			result[-2] = ["fat",  D, A, P, C]
			result[-1] = ["thin", P, B, C, D]
	return result

# ---- Collect unique edges and vertices ----
const EPSILON := 0.001

static func _vec_key(v: Vector2) -> String:
	return "%.3f,%.3f" % [v.x, v.y]

static func collect_geometry(tiles: Array, radius: float) -> Dictionary:
	var vertices: Dictionary = {}  # key → Vector2
	var edges: Dictionary    = {}  # key → {mid, angle, type}

	for t in tiles:
		var verts := [t[1], t[2], t[3], t[4]]
		# Cull tiles entirely outside the arena radius (with margin)
		var inside := false
		for v in verts:
			if v.length() < radius + 2.0:
				inside = true
				break
		if not inside:
			continue

		# Register vertices
		for v in verts:
			if v.length() <= radius + 1.0:
				vertices[_vec_key(v)] = v

		# Register edges (4 sides of rhombus)
		for i in range(4):
			var a: Vector2 = verts[i]
			var b: Vector2 = verts[(i + 1) % 4]
			# Canonical key: smaller x first (or y if x equal)
			var ka := _vec_key(a)
			var kb := _vec_key(b)
			var key := (ka + "|" + kb) if ka < kb else (kb + "|" + ka)
			if not edges.has(key):
				var mid   := (a + b) * 0.5
				var angle := atan2(b.y - a.y, b.x - a.x)  # radians from +X
				edges[key] = {
					"mid":   mid,
					"angle": angle,
					"len":   a.distance_to(b),
					"type":  t[0],
				}

	return {"vertices": vertices, "edges": edges}

# ---- Main ----
func _init() -> void:
	# Side length chosen so 2 inflations cover ~75m arena radius.
	# After 2 deflations side = initial / PHI^2. We want tiles ~10-15m,
	# so initial side = 10 * PHI^2 ≈ 26.2m.  After 2 steps → ~10m tiles.
	var initial_side := 10.0 * PHI * PHI  # ≈ 26.18m

	print("# Penrose P3 tiling — Arena One")
	print("# initial_side=%.4f  PHI=%.6f" % [initial_side, PHI])
	print("# Two deflation passes → tile side ≈ %.2fm" % [initial_side / (PHI * PHI)])
	print("# Pentagon V0 pointing +Z (north); team boundary at X=0")
	print("# Columns: arena X → output X,  arena Z → output Y")
	print()

	var tiles := make_sun(initial_side)
	print("# After seed: %d tiles" % tiles.size())
	tiles = deflate(tiles)
	print("# After deflation 1: %d tiles" % tiles.size())
	tiles = deflate(tiles)
	print("# After deflation 2: %d tiles" % tiles.size())
	print()

	var arena_radius := 72.0
	var geo := collect_geometry(tiles, arena_radius)
	var verts: Dictionary = geo["vertices"]
	var edges: Dictionary = geo["edges"]

	print("# VERTICES (%d)  format: VERTEX\tx\ty" % verts.size())
	for key in verts:
		var v: Vector2 = verts[key]
		print("VERTEX\t%.4f\t%.4f" % [v.x, v.y])

	print()
	print("# EDGES (%d)  format: EDGE\tmid_x\tmid_y\tangle_rad\tlength\ttile_type" % edges.size())
	for key in edges:
		var e: Dictionary = edges[key]
		var m: Vector2    = e["mid"]
		print("EDGE\t%.4f\t%.4f\t%.6f\t%.4f\t%s" % [
			m.x, m.y, e["angle"], e["len"], e["type"]
		])

	print()
	print("# Done.")
	quit()
