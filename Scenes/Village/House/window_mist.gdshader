shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 p = UV;
	float horizon = 0.69 + 0.025 * sin(p.x * 17.0 + TIME * 0.18);
	float band = 1.0 - smoothstep(0.0, 0.065, abs(p.y - horizon));
	float ripple = 0.54 + 0.24 * sin(p.x * 22.0 - TIME * 0.39 + p.y * 41.0)
		+ 0.22 * sin(p.x * 41.0 - TIME * 0.27 - p.y * 26.0);
	float opening = smoothstep(0.19, 0.29, p.x) * (1.0 - smoothstep(0.72, 0.81, p.x));
	vec3 mist = vec3(0.66, 0.50, 0.62);
	COLOR.rgb = mix(COLOR.rgb, mist, band * ripple * opening * 0.15);
}
