shader_type canvas_item;
render_mode unshaded;

uniform sampler2D stone_atlas : filter_nearest, repeat_disable;
uniform vec2 view_origin;
uniform vec2 view_size = vec2(1920.0, 1080.0);
uniform float depth = 0.0;
uniform float drift_time = 0.0;

float cell_random(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

float rock_cluster(vec2 world, float spacing) {
	vec2 cell = floor(world / spacing);
	float seed = cell_random(cell);
	vec2 offset = vec2(seed, cell_random(cell + vec2(31.0, 12.0))) * (spacing - 50.0);
	vec2 pixel = floor(mod(world, spacing) - offset);
	vec2 tile_pixel = mix(pixel, vec2(47.0) - pixel, step(vec2(0.5), vec2(seed, offset.y / (spacing - 50.0))));
	// Sample the inner stone corners from the existing terrain atlas.
	vec2 atlas_uv = (vec2(72.0, 24.0) + clamp(tile_pixel, vec2(0.0), vec2(47.0)) + 0.5) / vec2(textureSize(stone_atlas, 0));
	vec4 stone = texture(stone_atlas, atlas_uv);
	vec2 center = abs(pixel - 23.5);
	float edge = 1.0 - smoothstep(17.0, 24.0, max(center.x, center.y));
	return stone.a * max(stone.r, stone.b) * edge * smoothstep(0.14, 0.65, seed);
}

void fragment() {
	vec2 world = view_origin + UV * view_size;
	float distant = rock_cluster(world * 0.28, 62.0);
	float near = rock_cluster(world * 0.38 + vec2(270.0, 89.0), 81.0);
	vec2 dust_grid = (world * 0.47 + vec2(drift_time * 2.0, -drift_time * 1.1)) / 42.0;
	float dust_seed = cell_random(floor(dust_grid));
	vec2 fleck = abs(fract(dust_grid) - vec2(0.2 + 0.6 * dust_seed, 0.2 + 0.6 * fract(dust_seed * 13.7)));
	float dust = (1.0 - smoothstep(0.006, 0.019, max(fleck.x, fleck.y))) * step(0.68, dust_seed);
	float pools = 0.5 + 0.5 * sin(world.x * 0.002 + sin(world.y * 0.003));
	vec3 base = mix(vec3(0.051, 0.038, 0.079), vec3(0.029, 0.025, 0.055), depth);
	base += vec3(0.018, 0.010, 0.021) * pools;
	base += vec3(0.090, 0.048, 0.124) * distant;
	base += vec3(0.126, 0.060, 0.153) * near;
	COLOR = vec4(base + vec3(0.085, 0.059, 0.097) * dust, 1.0);
}
