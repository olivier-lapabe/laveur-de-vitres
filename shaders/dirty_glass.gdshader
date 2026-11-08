shader_type spatial;
render_mode blend_mix, cull_back;

// A shop window covered in two kinds of dirt:
// - dust: a matte, light grey-brown haze, thicker near the frame and the bottom;
// - grease: darker, slightly shiny marks left by hands, fingers and noses.

uniform vec4 glass_color : source_color = vec4(0.85, 0.92, 0.96, 0.05);
uniform vec4 dust_color : source_color = vec4(0.66, 0.6, 0.5, 1.0);
uniform vec4 grease_color : source_color = vec4(0.3, 0.24, 0.12, 1.0);
uniform float dust_strength : hint_range(0.0, 1.0) = 0.9;
uniform float grease_strength : hint_range(0.0, 1.0) = 1.0;
// Glass size in meters, so the dust grain keeps a real-world scale.
uniform vec2 glass_size = vec2(3.2, 2.2);
// Seamless fractal noise, tiled across the glass.
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Grease marks, one value per point of the glass (0 = none, 1 = thick).
uniform sampler2D grease_pattern : hint_default_black, filter_linear_mipmap, repeat_disable;

float dust_at(vec2 uv) {
	vec2 meters = uv * glass_size;
	float coarse = texture(noise_texture, meters * 0.35).r;
	float fine = texture(noise_texture, meters * 3.1 + vec2(0.37, 0.11)).r;
	// An even film of dust, with gentle variations rather than blotches.
	float dust = 0.45 + (coarse - 0.5) * 0.5 + (fine - 0.5) * 0.35;
	// Grime builds up along the frame, and rain splashes dirt onto the bottom.
	vec2 to_edge = min(uv, 1.0 - uv) * glass_size;
	float frame = 1.0 - smoothstep(0.0, 0.3, min(to_edge.x, to_edge.y));
	float bottom = smoothstep(0.6, 1.0, uv.y);
	dust += frame * 0.3 + bottom * 0.2;
	// Rain has run down the glass and left a few cleaner vertical tracks.
	float rain = texture(noise_texture, vec2(meters.x * 2.5, meters.y * 0.12) + vec2(0.5, 0.2)).r;
	dust *= mix(1.0, 0.75, smoothstep(0.62, 0.78, rain));
	return clamp(dust, 0.0, 1.0);
}

void fragment() {
	// Boost faint marks so even a light touch reads as grease.
	float grease = smoothstep(0.0, 0.55, texture(grease_pattern, UV).r) * grease_strength;
	// Hands and sleeves pushed the dust aside where they left grease.
	float dust = dust_at(UV) * dust_strength * (1.0 - grease * 0.75);

	vec3 color = mix(glass_color.rgb, dust_color.rgb, dust);
	float alpha = mix(glass_color.a, 0.8, dust);
	color = mix(color, grease_color.rgb, grease);
	alpha = mix(alpha, 0.85, grease);

	ALBEDO = color;
	ALPHA = alpha;
	// Clean glass is mirror-smooth, dust is matte, grease has an oily sheen.
	ROUGHNESS = mix(mix(0.03, 0.95, dust), 0.18, grease);
	SPECULAR = mix(mix(0.5, 0.15, dust), 0.7, grease);
}
