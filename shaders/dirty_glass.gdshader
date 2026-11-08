shader_type spatial;
render_mode blend_mix, cull_back;

// A shop window covered in one kind of dirt (decision D10), thicker in some
// places than others: a light haze over the whole pane, thicker near the frame
// and the bottom, and dark marks left by hands, fingers and noses.
// The script records what the player's hands did in dirt_state, and spit
// leaves wet spots that make the dirt translucent until they dry.

uniform vec4 glass_color : source_color = vec4(0.85, 0.92, 0.96, 0.05);
// Thin dirt is light grey-brown; thick dirt is dark brown.
uniform vec4 thin_dirt_color : source_color = vec4(0.66, 0.6, 0.5, 1.0);
uniform vec4 thick_dirt_color : source_color = vec4(0.3, 0.24, 0.12, 1.0);
// Glass size in meters, so the dirt grain keeps a real-world scale.
uniform vec2 glass_size = vec2(3.2, 2.2);
// Seamless fractal noise, tiled across the glass.
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Thick marks, one value per point of the glass (0 = none, 1 = thick).
uniform sampler2D marks_pattern : hint_default_black, filter_linear_mipmap, repeat_disable;
// R: share of the original dirt left, A: dirt smeared on by hands.
uniform sampler2D dirt_state : hint_default_white, filter_linear, repeat_disable;
// x, y: UV of a spit spot; z: its radius in meters; w: how wet it still is
// (1 = fully wet; above 1 the spit is fresh and still frothy, up to about 1.67).
uniform vec4 wet_spots[8];

float haze_at(vec2 uv) {
	vec2 meters = uv * glass_size;
	float coarse = texture(noise_texture, meters * 0.35).r;
	float fine = texture(noise_texture, meters * 3.1 + vec2(0.37, 0.11)).r;
	// An even film, with gentle variations rather than blotches.
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
	// Boost faint marks and smears so even a light touch shows.
	float marks = smoothstep(0.0, 0.55, texture(marks_pattern, UV).r);
	float smeared = smoothstep(0.0, 0.55, state.a);
	// Dirt thickness: from 0 (clean) through about 0.6 (haze) to 1.5 (thick mark).
	float thickness = (haze_at(UV) * 0.85 + marks * 0.9) * state.r + smeared * 0.9;
	float coverage = smoothstep(0.0, 0.9, thickness);
	vec3 dirt_tint = mix(thin_dirt_color.rgb, thick_dirt_color.rgb, smoothstep(0.65, 1.2, thickness));
	vec2 spit = spit_at(UV);
	float wet = spit.x;

	// Wet dirt soaks up and turns dark and see-through, like a wet patch on a dusty window.
	dirt_tint = mix(dirt_tint, dirt_tint * 0.35, wet);
	vec3 color = mix(glass_color.rgb, dirt_tint, coverage);
	float alpha = mix(glass_color.a, 0.85 * (1.0 - 0.7 * wet), coverage);
	// The edge of the water holds a darker line of dirt.
	float rim = smoothstep(0.05, 0.35, wet) * (1.0 - smoothstep(0.35, 0.8, wet));
	color = mix(color, thin_dirt_color.rgb * 0.3, rim * 0.6);
	alpha = max(alpha, rim * 0.55);
	// Fresh spit: small white bubbles.
	float bubbles = step(0.72, texture(noise_texture, UV * glass_size * 9.0).r) * spit.y;
	color = mix(color, vec3(0.95), bubbles);
	alpha = max(alpha, bubbles * 0.85);

	ALBEDO = color;
	ALPHA = alpha;
	// Clean glass is mirror-smooth, dirt is matte, water is very glossy.
	ROUGHNESS = mix(mix(0.03, 0.9, coverage), 0.0, wet);
	SPECULAR = mix(mix(0.5, 0.2, coverage), 1.0, wet);
}
