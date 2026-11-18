shader_type spatial;
// T473: the charging Taurus's red aura (Mech._charge_aura) -- a soft additive haze around the whole
// body, brightest toward its middle, fading out at the rim and toward the ground (no hard line where
// it meets the floor). k = speed / top speed.
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.08, 0.03);
uniform float k = 0.0;
const float PEAK = 0.5;  // at the top speed: a haze, not a red blob over the body
varying float local_y;

void vertex() {
	local_y = VERTEX.y;
}

void fragment() {
	float f = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float floor_fade = smoothstep(-1.3, -0.3, local_y);
	ALBEDO = tint * (PEAK * k * f * f * floor_fade);
}
