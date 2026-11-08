shader_type spatial;

// Procedural facade: a grid of windows on every vertical face, laid out in
// world space so any box gets floors of the same height. Below
// ground_floor_height the wall is plain stone, where the shops are.

uniform vec4 wall_color : source_color = vec4(0.66, 0.64, 0.6, 1.0);
uniform vec4 window_color : source_color = vec4(0.2, 0.27, 0.34, 1.0);
uniform vec4 ground_floor_color : source_color = vec4(0.52, 0.5, 0.47, 1.0);
uniform float floor_height = 3.2;
uniform float bay_width = 1.6;
uniform float ground_floor_height = 4.8;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 on_face = abs(world_normal.x) > 0.5 ? world_position.zy : world_position.xy;
	vec2 grid = vec2(on_face.x / bay_width, (on_face.y - ground_floor_height) / floor_height);
	vec2 cell = fract(grid);
	float window = step(0.12, cell.x) * step(cell.x, 0.88) * step(0.28, cell.y) * step(cell.y, 0.92);
	// Far away the grid gets smaller than a pixel: fade to its average instead of flickering.
	vec2 footprint = fwidth(grid);
	window = mix(window, 0.45, clamp(max(footprint.x, footprint.y) * 2.0, 0.0, 1.0));

	float upper = step(ground_floor_height, world_position.y);
	float is_window = window * upper;
	vec3 wall = mix(ground_floor_color.rgb, wall_color.rgb, upper);
	ALBEDO = mix(wall, window_color.rgb, is_window);
	ROUGHNESS = mix(0.85, 0.12, is_window);
	METALLIC = mix(0.0, 0.3, is_window);
}
