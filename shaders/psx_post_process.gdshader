shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float dither_amount : hint_range(0.0, 1.0) = 0.3;
uniform float color_depth : hint_range(1.0, 32.0) = 16.0;
uniform bool enable_dithering = true;
uniform bool enable_scanlines = false;
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.2;

// Bayer matrix for dithering
const mat4 bayer_matrix = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

float dither(vec2 pos) {
	int x = int(mod(pos.x, 4.0));
	int y = int(mod(pos.y, 4.0));
	return bayer_matrix[x][y];
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 color = texture(screen_texture, uv);

	// Color depth reduction
	float levels = color_depth;
	color.r = floor(color.r * levels) / levels;
	color.g = floor(color.g * levels) / levels;
	color.b = floor(color.b * levels) / levels;

	// Dithering
	if (enable_dithering) {
		float dither_value = dither(FRAGCOORD.xy) * dither_amount;
		color.rgb += (dither_value - dither_amount * 0.5) * 0.1;
	}

	// Scanlines
	if (enable_scanlines) {
		float scanline = sin(FRAGCOORD.y * 3.14159 * 2.0) * scanline_intensity;
		color.rgb -= scanline;
	}

	COLOR = color;
}
