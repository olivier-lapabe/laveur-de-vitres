shader_type spatial;
render_mode blend_mix, cull_back;

// A shop window covered in two kinds of dirt:
// - dust: a matte, light grey-brown haze, thicker near the frame and the bottom;
// - grease: darker, slightly shiny marks left by hands, fingers and noses.
// The script records what the player's hands did in dirt_state, and spit
// leaves wet spots that make the dust translucent until they dry.

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
// R: dust left, G: original grease left, A: grease spread by hands.
uniform sampler2D dirt_state : hint_default_white, filter_linear, repeat_disable;
// x, y: UV of a spit spot; z: its radius in meters; w: how wet it still is
// (1 = fully wet; above 1 the spit is fresh and still frothy, up to about 1.67).
uniform vec4 wet_spots[8];

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

// Returns (wetness, froth), both from 0 to 1.
vec2 spit_at(vec2 uv) {
	// Irregular edges, like a real splash.
	float wobble = 0.85 + 0.3 * texture(noise_texture, uv * glass_size * 1.5).r;
	float wet = 0.0;
	float froth = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 spot = wet_spots[i];
		if (spot.w <= 0.0) {
			continue;
		}
		float spot_distance = length((uv - spot.xy) * glass_size) / spot.z * wobble;
		float inside = 1.0 - smoothstep(0.55, 1.0, spot_distance);
		wet = max(wet, min(spot.w, 1.0) * inside);
		// Fresh spit is frothy in its middle.
		froth = max(froth, clamp((spot.w - 1.0) * 1.5, 0.0, 1.0) * (1.0 - smoothstep(0.0, 0.6, spot_distance)));
	}
	return vec2(wet, froth);
}

void fragment() {
	vec4 state = texture(dirt_state, UV);
	float grease_amount = texture(grease_pattern, UV).r * state.g + state.a;
	// Boost faint marks so even a light touch reads as grease.
	float grease = smoothstep(0.0, 0.55, grease_amount) * grease_strength;
	// Hands and sleeves pushed the dust aside where they left grease.
	float dust = dust_at(UV) * state.r * dust_strength * (1.0 - grease * 0.75);
	vec2 spit = spit_at(UV);
	float wet = spit.x;

	// Wet dust soaks up and turns dark and see-through, like a wet patch on a dusty window.
	vec3 dust_tint = mix(dust_color.rgb, dust_color.rgb * 0.35, wet);
	vec3 color = mix(glass_color.rgb, dust_tint, dust);
	float alpha = mix(glass_color.a, 0.8 * (1.0 - 0.75 * wet), dust);
	color = mix(color, grease_color.rgb, grease);
	alpha = mix(alpha, 0.85, grease);
	// The edge of the water holds a darker line of dirt.
	float rim = smoothstep(0.05, 0.35, wet) * (1.0 - smoothstep(0.35, 0.8, wet));
	color = mix(color, dust_color.rgb * 0.3, rim * 0.6);
	alpha = max(alpha, rim * 0.55);
	// Fresh spit: small white bubbles.
	float bubbles = step(0.72, texture(noise_texture, UV * glass_size * 9.0).r) * spit.y;
	color = mix(color, vec3(0.95), bubbles);
	alpha = max(alpha, bubbles * 0.85);

	ALBEDO = color;
	ALPHA = alpha;
	// Clean glass is mirror-smooth, dust is matte, grease has an oily sheen, water is very glossy.
	ROUGHNESS = mix(mix(mix(0.03, 0.95, dust), 0.18, grease), 0.0, wet);
	SPECULAR = mix(mix(mix(0.5, 0.15, dust), 0.7, grease), 1.0, wet);
}
