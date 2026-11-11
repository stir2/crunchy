shader_type canvas_item;
render_mode unshaded;

instance uniform float phase = 0.0;

void fragment() {
	float time = fract(TIME * 0.23 + phase);
	float head = time * time * 5.0;
	float trail = smoothstep(0.0, 0.012, head - UV.y) * (1.0 - smoothstep(0.024, 0.049, head - UV.y));
	float width = 1.0 - smoothstep(0.08, 0.30, abs(UV.x - 0.5));
	COLOR = vec4(0.57, 0.54, 0.73, trail * width * (1.0 - smoothstep(0.78, 1.0, UV.y)) * 0.52);
}
