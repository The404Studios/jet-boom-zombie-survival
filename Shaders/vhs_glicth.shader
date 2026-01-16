shader_type canvas_item;

// Simple VHS glitch effect shader
// Note: This is a Godot 3.x style shader kept for compatibility

uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.1;
uniform float scan_line_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.1;

float random(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;

	// Random glitch offset
	float glitch = random(vec2(TIME * 0.1, uv.y)) * glitch_intensity;
	if (random(vec2(TIME, 0.0)) > 0.95) {
		uv.x += glitch * 0.1;
	}

	// Scan lines
	float scan_line = sin(uv.y * 400.0) * scan_line_intensity;

	// Sample texture
	vec4 color = texture(TEXTURE, uv);

	// Add noise
	float noise = random(uv + TIME) * noise_intensity;

	// Apply effects
	color.rgb += scan_line;
	color.rgb += noise;

	COLOR = color;
}
