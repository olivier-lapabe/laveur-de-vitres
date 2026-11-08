extends MeshInstance3D
## The storefront glass and its dirt. Both dirt patterns are generated once, at
## startup: noise for the dust haze, and grease marks stamped where people
## touched the glass.

## Pattern resolution for the grease marks.
const PIXELS_PER_METER := 160.0

## Glass size in meters; must match the QuadMesh.
@export var glass_size := Vector2(3.2, 2.2)
## Height of the bottom edge of the glass above the street, in meters.
@export var bottom_height := 0.5

var _grease := PackedByteArray()
var _pattern_size := Vector2i.ZERO
var _breakup := FastNoiseLite.new()


func _ready() -> void:
	var glass_material := material_override as ShaderMaterial
	glass_material.set_shader_parameter("glass_size", glass_size)
	glass_material.set_shader_parameter("noise_texture", _make_noise_texture())
	glass_material.set_shader_parameter("grease_pattern", _make_grease_pattern())


func _make_noise_texture() -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 1.0 / 48.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var image := noise.get_seamless_image(256, 256)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Positions below are in meters: x from the left edge of the glass, y as the
## height above the street.
func _make_grease_pattern() -> ImageTexture:
	_pattern_size = Vector2i((glass_size * PIXELS_PER_METER).round())
	_grease.resize(_pattern_size.x * _pattern_size.y)
	_grease.fill(0)
	_breakup.seed = 5
	_breakup.frequency = 0.08

	# Someone once wiped the glass with a sleeve and only spread the grease around.
	_smear(Vector2(1.0, 1.45), Vector2(0.4, 0.08), 18.0, 0.75)
	_smear(Vector2(1.15, 1.28), Vector2(0.34, 0.07), -12.0, 0.65)
	_smear(Vector2(2.3, 1.55), Vector2(0.32, 0.07), 8.0, 0.6)
	# Adults leaning on the glass to look inside.
	_handprint(Vector2(2.45, 1.35), 1.0, -8.0, 0.95)
	_handprint(Vector2(0.55, 1.5), 1.0, 12.0, 0.85)
	_handprint(Vector2(1.35, 1.65), 1.0, -4.0, 0.9)
	_handprint(Vector2(1.95, 1.72), 1.0, 6.0, 0.85)
	# Children pressing their hands and nose against the bakery window.
	_handprint(Vector2(1.55, 0.95), 0.65, -15.0, 1.0)
	_handprint(Vector2(1.95, 0.9), 0.65, 10.0, 1.0)
	_smear(Vector2(1.75, 1.02), Vector2(0.035, 0.028), 0.0, 0.9)
	_handprint(Vector2(2.9, 0.8), 0.65, 5.0, 0.9)
	# Stray fingertips.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for _i in 14:
		var at := Vector2(rng.randf_range(0.2, 3.0), rng.randf_range(0.7, 1.7))
		_smear(at, Vector2(0.011, 0.014), rng.randf_range(-40.0, 40.0), rng.randf_range(0.4, 0.8), true)

	var image := Image.create_from_data(_pattern_size.x, _pattern_size.y, false, Image.FORMAT_L8, _grease)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _handprint(center: Vector2, size: float, angle_degrees: float, strength: float) -> void:
	var angle := deg_to_rad(angle_degrees)
	_smear(center, Vector2(0.045, 0.052) * size, angle_degrees, strength * 0.8)
	var fingers: Array[Vector2] = [
		Vector2(-0.032, 0.085), Vector2(-0.011, 0.097), Vector2(0.011, 0.094), Vector2(0.031, 0.08),
	]
	for finger in fingers:
		_smear(center + (finger * size).rotated(angle), Vector2(0.0105, 0.03) * size, angle_degrees, strength, true)
	var thumb := Vector2(-0.058, 0.012)
	_smear(center + (thumb * size).rotated(angle), Vector2(0.012, 0.028) * size, angle_degrees + 35.0, strength, true)


## Adds an elliptic mark. Ridged marks get the rings of a fingerprint.
func _smear(center: Vector2, radii: Vector2, angle_degrees: float, strength: float, ridged := false) -> void:
	var middle := Vector2(center.x, glass_size.y - (center.y - bottom_height)) * PIXELS_PER_METER
	var radii_px := radii * PIXELS_PER_METER
	var reach := ceili(maxf(radii_px.x, radii_px.y)) + 1
	# Pixel rows go down while heights go up, hence the minus sign.
	var angle := -deg_to_rad(angle_degrees)
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	for py in range(maxi(0, int(middle.y) - reach), mini(_pattern_size.y, int(middle.y) + reach + 1)):
		for px in range(maxi(0, int(middle.x) - reach), mini(_pattern_size.x, int(middle.x) + reach + 1)):
			var offset := Vector2(px - middle.x, py - middle.y)
			var local := Vector2(offset.x * cos_a + offset.y * sin_a, -offset.x * sin_a + offset.y * cos_a)
			var distance := (local / radii_px).length()
			if distance >= 1.0:
				continue
			var amount := strength * (1.0 - smoothstep(0.5, 1.0, distance))
			amount *= 0.65 + 0.35 * _breakup.get_noise_2d(px, py)
			if ridged:
				amount *= 0.7 + 0.3 * sin(distance * 18.0)
			var index := py * _pattern_size.x + px
			_grease[index] = maxi(_grease[index], clampi(int(amount * 255.0), 0, 255))
