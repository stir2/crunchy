shader_type canvas_item;
render_mode unshaded;

uniform float ink_cutoff = 0.49;
uniform vec2 left_trim = vec2(0.0);

void fragment() {
	// Keep the outline one source texel wide and inside the printed silhouette.
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	float excluded = (1.0 - step(left_trim.x, pixel.x)) * step(left_trim.y, pixel.y);
	float ink = (1.0 - step(ink_cutoff, COLOR.g)) * (1.0 - excluded);
	vec2 x = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	vec2 y = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
	float neighbor = max(texture(TEXTURE, UV - x).g, texture(TEXTURE, UV + x).g);
	neighbor = max(neighbor, max(texture(TEXTURE, UV - y).g, texture(TEXTURE, UV + y).g));
	vec3 highlight = COLOR.rgb * vec3(0.80, 0.73, 0.75);
	highlight = mix(highlight, vec3(0.94, 0.75, 0.46), step(ink_cutoff, neighbor) * 0.78);
	COLOR = vec4(highlight, COLOR.a * ink);
}
