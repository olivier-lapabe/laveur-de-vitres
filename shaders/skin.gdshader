shader_type spatial;

// Bare skin that collects grime: dark blotches appear and spread as dirt
// goes from 0 (clean) to 1 (covered), so a dirty hand reads as dirty.

uniform vec4 skin_color : source_color = vec4(0.72, 0.52, 0.41, 1.0);
uniform vec4 grime_color : source_color = vec4(0.22, 0.18, 0.12, 1.0);
uniform float dirt : hint_range(0.0, 1.0) = 0.0;
// Wet skin is shiny.
uniform float wet : hint_range(0.0, 1.0) = 0.0;
// Blotches per meter of skin.
uniform float blotch_scale = 70.0;

varying vec3 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// Object space, so the blotches stay put on the skin.
	local_position = VERTEX;
}

void fragment() {
	vec3 p = local_position * blotch_scale;
	float pattern = value_noise(p.xy + p.z * 0.7) * 0.65 + value_noise(p.yz * 2.3 + 5.0) * 0.35;
	// Points whose pattern is below the dirt level are covered: the grime spreads as dirt grows.
	float covered = smoothstep(pattern - 0.08, pattern + 0.08, dirt * 1.15);
	ALBEDO = mix(skin_color.rgb, grime_color.rgb, covered * 0.92);
	// Grime is a little greasy.
	ROUGHNESS = mix(mix(0.75, 0.45, covered), 0.15, wet);
	SPECULAR = mix(0.5, 0.9, wet);
}
