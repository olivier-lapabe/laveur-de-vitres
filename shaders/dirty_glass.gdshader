shader_type spatial;
render_mode blend_mix, cull_back;

// A shop window covered in two kinds of dirt:
// - dust: a matte, light grey-brown haze, thicker near the frame and the bottom;
// - grease: darker, slightly shiny marks left by hands, fingers and noses.

uniform vec4 glass_color : source_color = vec4(0.85, 0.92, 0.96, 0.06);
uniform vec4 dust_color : source_color = vec4(0.63, 0.58, 0.5, 1.0);
uniform vec4 grease_color : source_color = vec4(0.36, 0.33, 0.24, 1.0);
uniform float dust_strength : hint_range(0.0, 1.0) = 0.9;
uniform float grease_strength : hint_range(0.0, 1.0) = 0.85;
// Glass size in meters, so the dust grain keeps a real-world scale.
uniform vec2 glass_size = vec2(3.2, 2.2);
// Seamless fractal noise, tiled across the glass.
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Grease marks, one value per point of the glass (0 = none, 1 = thick).
uniform sampler2D grease_pattern : hint_default_black, filter_linear_mipmap, repeat_disable;

float dust_at(vec2 uv) {
	vec2 meters = uv * glass_size;
	float coarse = texture(noise_texture, meters * 0.35).r;
	float fine = texture(noise_texture, meters * 2.7 + vec2(0.37, 0.11)).r;
	float dust = smoothstep(0.2, 0.8, coarse) * 0.65 + fine * 0.35;
	// Grime builds up along the frame, and rain splashes dirt onto the bottom.
	vec2 to_edge = min(uv, 1.0 - uv) * glass_size;
	float frame = 1.0 - smoothstep(0.0, 0.3, min(to_edge.x, to_edge.y));
	float bottom = smoothstep(0.6, 1.0, uv.y);
	dust = dust * 0.7 + frame * 0.35 + bottom * 0.25;
	// Rain has run down the glass and left a few cleaner vertical tracks.
	float rain = texture(noise_texture, vec2(meters.x * 2.5, meters.y * 0.12) + vec2(0.5, 0.2)).r;
	dust *= mix(1.0, 0.5, smoothstep(0.62, 0.78, rain));
	return clamp(dust, 0.0, 1.0);
}

void fragment() {
	float dust = dust_at(UV) * dust_strength;
	float grease = texture(grease_pattern, UV).r * grease_strength;

	vec3 color = mix(glass_color.rgb, dust_color.rgb, dust);
	float alpha = mix(glass_color.a, 0.88, dust);
	color = mix(color, grease_color.rgb, grease);
	alpha = mix(alpha, 0.8, grease);

	ALBEDO = color;
	ALPHA = alpha;
	// Clean glass is mirror-smooth, dust is matte, grease has a dull sheen.
	ROUGHNESS = mix(mix(0.03, 0.9, dust), 0.3, grease);
	SPECULAR = 0.5;
}
