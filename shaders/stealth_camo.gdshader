shader_type spatial;
render_mode cull_back, specular_disabled;

// T201: active camouflage. The mech takes on the colour of what is behind it -- a wide
// 5x5 blur of the screen around the fragment -- but stays lit, so its shape still reads
// as a blurry, surroundings-coloured silhouette. Before T201 it drew the exact pixels
// behind it, unshaded: the mech vanished.
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform float spread = 0.03;  // UV per blur step (5 steps across = 0.12 of the screen)

void fragment() {
	vec3 c = vec3(0.0);
	for (int i = -2; i <= 2; i++) {
		for (int j = -2; j <= 2; j++) {
			c += texture(SCREEN_TEXTURE, SCREEN_UV + vec2(float(i), float(j)) * spread).rgb;
		}
	}
	ALBEDO = c / 25.0;
	ROUGHNESS = 1.0;
}
