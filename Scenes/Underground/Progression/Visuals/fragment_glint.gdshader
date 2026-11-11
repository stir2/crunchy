shader_type canvas_item;
render_mode unshaded;

varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 art = texture(TEXTURE, UV) * tint;
	float cycle = fract(TIME * 0.32);
	float sweep = floor(mix(-4.0, 25.0, clamp(cycle * 4.0, 0.0, 1.0)));
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
	float diagonal = texel.x + floor((15.0 - texel.y) * 0.5);
	float glint = (1.0 - step(1.0, abs(diagonal - sweep))) * 0.80;
	glint += (1.0 - step(1.0, abs(diagonal - sweep - 1.0))) * 0.32;
	COLOR = vec4(mix(art.rgb, vec3(1.0, 0.91, 0.68), glint), art.a);
}
