shader_type spatial;
render_mode unshaded, cull_back, vertex_lighting;

uniform sampler2D texture_albedo : source_color;
uniform float vertex_snap_amount : hint_range(0.0, 1.0) = 0.05;
uniform float texture_wobble : hint_range(0.0, 1.0) = 0.5;
uniform bool enable_affine_mapping = true;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float vertex_jitter : hint_range(0.0, 1.0) = 0.1;

varying vec3 vertex_pos;
varying vec2 uv_interp;
varying vec3 vertex_normal;

void vertex() {
	// PSX-style vertex snapping
	vec4 snap_to_pixel = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	snap_to_pixel.xyz = snap_to_pixel.xyz / snap_to_pixel.w;

	float grid_size = 100.0 / vertex_snap_amount;
	snap_to_pixel.x = floor(grid_size * snap_to_pixel.x) / grid_size;
	snap_to_pixel.y = floor(grid_size * snap_to_pixel.y) / grid_size;

	snap_to_pixel.xyz *= snap_to_pixel.w;

	POSITION = snap_to_pixel;

	// Vertex jitter for PSX effect
	vertex_pos = VERTEX;
	uv_interp = UV;
	vertex_normal = NORMAL;
}

void fragment() {
	vec2 uv = uv_interp;

	// Affine texture mapping (PSX-style)
	if (enable_affine_mapping) {
		float z = 1.0 / VERTEX.z;
		uv = uv * z;
	}

	// Sample texture
	vec4 tex = texture(texture_albedo, uv);

	// Apply color
	ALBEDO = tex.rgb * albedo_color.rgb;
	ALPHA = tex.a * albedo_color.a;

	// Simple vertex lighting
	float NdotL = max(dot(vertex_normal, vec3(0.5, 1.0, 0.5)), 0.0);
	ALBEDO *= mix(0.3, 1.0, NdotL);
}
