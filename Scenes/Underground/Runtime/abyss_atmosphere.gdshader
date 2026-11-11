shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform sampler2D fog_noise : filter_linear, repeat_enable;
uniform vec2 view_origin;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform vec2 player_uv = vec2(0.5);
uniform float depth = 0.0;
uniform float fog_density = 0.04;
uniform float drift_time = 0.0;

void fragment() {
	vec2 world = view_origin + UV * view_size;
	vec2 drift = vec2(drift_time * 0.009, drift_time * -0.004);
	float broad = texture(fog_noise, world / vec2(900.0, 480.0) + drift).r;
	float wisps = texture(fog_noise, world / vec2(470.0, 205.0) - drift * 0.55).r;
	float mist = smoothstep(0.30 + (wisps - 0.5) * 0.16 * depth, 0.76, broad * 0.72 + wisps * 0.28);


	vec2 from_player = (UV - player_uv) * view_size / view_size.y;
	float glow = 1.0 - smoothstep(0.07, 0.53, length(from_player));
	float edge = smoothstep(0.20, 0.74, length((UV - 0.5) * vec2(1.0, 0.85)));
	float shade = (0.035 + 0.065 * depth) * (1.0 - glow) + edge * 0.13;
	float fog = fog_density * mist * (1.0 - 0.52 * glow);
	vec3 light = vec3(0.024, 0.013, 0.013) * glow;
	vec3 fog_color = mix(vec3(0.23, 0.16, 0.29), vec3(0.23, 0.19, 0.35), depth);
	// Encode the scene attenuation in alpha and the light and mist in RGB.
	COLOR = vec4(light * (1.0 - fog) + fog_color * fog, shade + fog - shade * fog);
}
