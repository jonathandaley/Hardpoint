shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 albedo_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float panel_scale : hint_range(0.1, 10.0) = 1.5;
uniform float line_width : hint_range(0.001, 0.5) = 0.04;
uniform float line_darkness : hint_range(0.0, 1.0) = 0.35;
uniform float noise_scale : hint_range(0.1, 20.0) = 6.0;
uniform float noise_strength : hint_range(0.0, 0.2) = 0.04;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 blend = abs(world_normal);
	blend = normalize(max(blend, vec3(0.001)));
	blend /= blend.x + blend.y + blend.z;

	vec2 uv_x = world_pos.yz * panel_scale;
	vec2 uv_y = world_pos.xz * panel_scale;
	vec2 uv_z = world_pos.xy * panel_scale;

	// sin*sin noise approximation - no texture needed
	float nx = sin(uv_x.x * noise_scale) * sin(uv_x.y * noise_scale) * noise_strength;
	float ny = sin(uv_y.x * noise_scale) * sin(uv_y.y * noise_scale) * noise_strength;
	float nz = sin(uv_z.x * noise_scale) * sin(uv_z.y * noise_scale) * noise_strength;

	vec2 fx = fract(uv_x + vec2(nx));
	vec2 fy = fract(uv_y + vec2(ny));
	vec2 fz = fract(uv_z + vec2(nz));

	float lw = line_width;
	// inverted smoothstep: 1 at seam (near 0 or near 1), 0 away from seam
	float mx = max(
		max(smoothstep(lw, 0.0, fx.x), smoothstep(1.0 - lw, 1.0, fx.x)),
		max(smoothstep(lw, 0.0, fx.y), smoothstep(1.0 - lw, 1.0, fx.y))
	);
	float my = max(
		max(smoothstep(lw, 0.0, fy.x), smoothstep(1.0 - lw, 1.0, fy.x)),
		max(smoothstep(lw, 0.0, fy.y), smoothstep(1.0 - lw, 1.0, fy.y))
	);
	float mz = max(
		max(smoothstep(lw, 0.0, fz.x), smoothstep(1.0 - lw, 1.0, fz.x)),
		max(smoothstep(lw, 0.0, fz.y), smoothstep(1.0 - lw, 1.0, fz.y))
	);

	float line_mask = mx * blend.x + my * blend.y + mz * blend.z;

	vec3 base = albedo_color.rgb;
	ALBEDO = mix(base, base * (1.0 - line_darkness), line_mask);
}
