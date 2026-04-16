shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;

uniform float fill : hint_range(0.0, 1.0) = 1.0;
uniform vec3 bar_color : source_color = vec3(1.0, 0.1, 0.05);
uniform vec3 bg_color  : source_color = vec3(0.1, 0.1, 0.1);

void vertex() {
	// Billboard: get mesh center in view space, then add vertex offset screen-aligned
	vec4 view_center = VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	POSITION = PROJECTION_MATRIX * (view_center + vec4(VERTEX.xy, 0.0, 0.0));
}

void fragment() {
	ALBEDO = UV.x < fill ? bar_color : bg_color;
}
