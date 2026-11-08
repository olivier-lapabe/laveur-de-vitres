class_name DirtyGlass
extends MeshInstance3D
## The storefront glass and its dirt.
##
## Two dirt patterns are generated at startup: noise for the dust haze, and
## grease marks stamped where people touched the glass. A state texture then
## records what the player's hands did to them, and spit leaves wet spots that
## dry after a while.

## Pattern resolution for the grease marks.
const PIXELS_PER_METER := 160.0
## Resolution of the cleaning state: coarser, because a script updates it.
const STATE_PIXELS_PER_METER := 100.0

# Tuning of the bare-hand gesture. Amounts are fractions from 0 to 1.
## Radius of the area a hand rubs, in meters.
const HAND_RADIUS := 0.09
## Share of the dirt under the middle of the hand removed per meter of rubbing, on wet glass.
const RUB_RATE := 7.0
## Rubbing dry glass works this much as well as rubbing wet glass: barely.
const DRY_RUB_FACTOR := 0.08
## Grease comes off this much as easily as dust.
const GREASE_RESISTANCE := 0.6
## Share of the grease loosened by the hand that gets spread around instead of picked up.
const GREASE_SPREAD := 0.6
## Grease a fully dirty hand leaves per meter of rubbing.
const HAND_DEPOSIT := 1.5
## Film that bare skin always leaves behind: glass washed by hand is never spotless.
const BARE_HAND_RESIDUE := 0.08
## How much dirtier the hand gets per unit of dirt it takes off the glass.
## Dust counts for less than grease (DUST_PICKUP).
const HAND_PICKUP := 0.9
## Dust soils the hand this much compared to grease.
const DUST_PICKUP := 0.1
## Radius of the patch one spit wets, in meters.
const SPIT_RADIUS := 0.22
## Seconds before spit has dried.
const SPIT_DRY_SECONDS := 15.0
## Wet spots tracked at once; must match the shader's wet_spots array.
const MAX_WET_SPOTS := 8

## Glass size in meters; must match the QuadMesh.
@export var glass_size := Vector2(3.2, 2.2)
## Height of the bottom edge of the glass above the street, in meters.
@export var bottom_height := 0.5

var _grease := PackedByteArray()
var _pattern_size := Vector2i.ZERO
var _breakup := FastNoiseLite.new()

## RGBA8 per state pixel, sent to the shader. R: dust left, G: original grease
## left, A: grease spread by hands (B is unused).
var _state := PackedByteArray()
## The same values as floats, for the cleaning maths: rounding them to bytes on
## every rub made even useless rubbing wear the dirt away.
var _dust := PackedFloat32Array()
var _grease_left := PackedFloat32Array()
var _spread := PackedFloat32Array()
var _state_size := Vector2i.ZERO
var _state_image: Image
var _state_texture: ImageTexture
var _state_changed := false
## The grease pattern at state resolution, to know how much grease a pixel holds.
var _grease_base := PackedByteArray()
## x, y: UV of the spot; z: radius in meters; w: seconds before it is dry.
var _wet_spots: Array[Vector4] = []

## Whether the last rub was on dry glass, for the player's hint.
var last_rub_was_dry := false

@onready var _material := material_override as ShaderMaterial


func _ready() -> void:
	_material.set_shader_parameter("glass_size", glass_size)
	_material.set_shader_parameter("noise_texture", _make_noise_texture())
	var grease_image := _make_grease_image()
	_material.set_shader_parameter("grease_pattern", ImageTexture.create_from_image(grease_image))
	_init_state(grease_image)
	_send_wet_spots()


func _process(delta: float) -> void:
	if not _wet_spots.is_empty():
		for i in range(_wet_spots.size() - 1, -1, -1):
			var spot := _wet_spots[i]
			spot.w -= delta
			if spot.w <= 0.0:
				_wet_spots.remove_at(i)
			else:
				_wet_spots[i] = spot
		_send_wet_spots()
	if _state_changed:
		_state_image.set_data(_state_size.x, _state_size.y, false, Image.FORMAT_RGBA8, _state)
		_state_texture.update(_state_image)
		_state_changed = false


## Where a ray meets the glass, as {"point", "uv", "distance"}; empty if it misses.
func intersect(origin: Vector3, direction: Vector3) -> Dictionary:
	var normal := get_normal()
	var facing := normal.dot(direction)
	if absf(facing) < 0.0001:
		return {}
	var distance := normal.dot(global_position - origin) / facing
	if distance <= 0.0:
		return {}
	var point := origin + direction * distance
	var uv := uv_at(point)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return {}
	return {"point": point, "uv": uv, "distance": distance}


## The glass coordinates (0 to 1, from the top left) of a point on its plane.
func uv_at(point: Vector3) -> Vector2:
	var local := to_local(point)
	return Vector2(local.x / glass_size.x + 0.5, 0.5 - local.y / glass_size.y)


## The direction the glass faces, toward the street.
func get_normal() -> Vector3:
	return global_transform.basis.z.normalized()


## Spit lands at uv and wets the glass around it until it dries.
func spit(uv: Vector2) -> void:
	if _wet_spots.size() >= MAX_WET_SPOTS:
		_wet_spots.pop_front()
	_wet_spots.append(Vector4(uv.x, uv.y, SPIT_RADIUS, SPIT_DRY_SECONDS))
	_send_wet_spots()


## How wet the glass is at uv, from 0 (dry) to 1.
func wetness_at(uv: Vector2) -> float:
	var wet := 0.0
	for spot in _wet_spots:
		var distance := ((uv - Vector2(spot.x, spot.y)) * glass_size).length() / spot.z
		wet = maxf(wet, _spot_strength(spot) * (1.0 - smoothstep(0.55, 1.0, distance)))
	return wet


## How much of the dust is left at uv, from 1 (untouched) to 0.
func dust_left_at(uv: Vector2) -> float:
	return _dust[_state_index(uv)]


## Grease at uv: what is left of the original marks plus what hands spread.
func grease_at(uv: Vector2) -> float:
	var i := _state_index(uv)
	return minf(1.0, _grease_base[i] / 255.0 * _grease_left[i] + _spread[i])


## Rubs the glass with a bare hand centered on uv, over stroke_length meters.
## hand_dirt (0 to 1) is how dirty the hand already is: a clean hand takes dirt
## off, a dirty one smears grease. Returns how much dirtier the hand gets.
func rub(uv: Vector2, stroke_length: float, hand_dirt: float) -> float:
	var center := Vector2(uv.x * _state_size.x, uv.y * _state_size.y)
	var radius := HAND_RADIUS * STATE_PIXELS_PER_METER
	var reach := ceili(radius)
	var wet_factor := lerpf(DRY_RUB_FACTOR, 1.0, wetness_at(uv))
	var picked := 0.0
	var pixels := 0
	for py in range(maxi(0, int(center.y) - reach), mini(_state_size.y, int(center.y) + reach + 1)):
		for px in range(maxi(0, int(center.x) - reach), mini(_state_size.x, int(center.x) + reach + 1)):
			var distance := Vector2(px + 0.5 - center.x, py + 0.5 - center.y).length() / radius
			if distance >= 1.0:
				continue
			var weight := 1.0 - distance * distance
			var effect := clampf(stroke_length * RUB_RATE * weight * wet_factor, 0.0, 1.0)
			var p := py * _state_size.x + px
			var dust := _dust[p]
			var grease_left := _grease_left[p]
			var spread := _spread[p]
			var base := _grease_base[p] / 255.0

			# Dust comes straight off.
			var dust_removed := dust * effect
			# Grease is loosened, and most of it is smeared around before it goes.
			var grease_loosened := grease_left * effect * GREASE_RESISTANCE
			var spread_removed := spread * effect * GREASE_RESISTANCE * (1.0 - hand_dirt)
			spread += base * grease_loosened * GREASE_SPREAD - spread_removed
			# A dirty hand leaves its grease on the glass.
			spread += hand_dirt * HAND_DEPOSIT * stroke_length * weight
			var residue := BARE_HAND_RESIDUE * weight * (0.6 + 0.4 * _breakup.get_noise_2d(px * 3.0, py * 3.0))
			spread = clampf(maxf(spread, residue), 0.0, 1.0)

			picked += dust_removed * DUST_PICKUP + base * grease_loosened * (1.0 - GREASE_SPREAD) + spread_removed
			pixels += 1
			dust -= dust_removed
			grease_left -= grease_loosened
			_dust[p] = dust
			_grease_left[p] = grease_left
			_spread[p] = spread
			_state[p * 4] = int(dust * 255.0 + 0.5)
			_state[p * 4 + 1] = int(grease_left * 255.0 + 0.5)
			_state[p * 4 + 3] = int(spread * 255.0 + 0.5)
	_state_changed = true
	last_rub_was_dry = wet_factor < 0.5
	return picked / maxf(pixels, 1) * HAND_PICKUP


func _state_index(uv: Vector2) -> int:
	var x := clampi(int(uv.x * _state_size.x), 0, _state_size.x - 1)
	var y := clampi(int(uv.y * _state_size.y), 0, _state_size.y - 1)
	return y * _state_size.x + x


func _init_state(grease_image: Image) -> void:
	_state_size = Vector2i((glass_size * STATE_PIXELS_PER_METER).round())
	_state_image = Image.create_empty(_state_size.x, _state_size.y, false, Image.FORMAT_RGBA8)
	_state_image.fill(Color(1, 1, 0, 0))
	_state = _state_image.get_data()
	var pixels := _state_size.x * _state_size.y
	_dust.resize(pixels)
	_dust.fill(1.0)
	_grease_left.resize(pixels)
	_grease_left.fill(1.0)
	_spread.resize(pixels)
	_spread.fill(0.0)
	_state_texture = ImageTexture.create_from_image(_state_image)
	_material.set_shader_parameter("dirt_state", _state_texture)
	var base := grease_image.duplicate() as Image
	base.clear_mipmaps()
	base.resize(_state_size.x, _state_size.y, Image.INTERPOLATE_BILINEAR)
	_grease_base = base.get_data()


## Spit stays fully wet for the first third of its life, then dries out.
func _spot_strength(spot: Vector4) -> float:
	return clampf(_spot_freshness(spot), 0.0, 1.0)


## From 1.5 when just spat to 0 when dry; above 1 the spit is still frothy.
func _spot_freshness(spot: Vector4) -> float:
	return spot.w / SPIT_DRY_SECONDS * 1.5


func _send_wet_spots() -> void:
	# A typed array, so the shader gets exactly x, y, z, w for each spot.
	var spots := PackedVector4Array()
	for spot in _wet_spots:
		spots.append(Vector4(spot.x, spot.y, spot.z, _spot_freshness(spot)))
	while spots.size() < MAX_WET_SPOTS:
		spots.append(Vector4.ZERO)
	_material.set_shader_parameter("wet_spots", spots)


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
func _make_grease_image() -> Image:
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
	_handprint(Vector2(2.45, 1.35), 1.1, -8.0, 0.95)
	_handprint(Vector2(0.55, 1.5), 1.1, 12.0, 0.85)
	_handprint(Vector2(1.35, 1.65), 1.1, -4.0, 0.9)
	_handprint(Vector2(1.95, 1.72), 1.1, 6.0, 0.85)
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
	return image


func _handprint(center: Vector2, size: float, angle_degrees: float, strength: float) -> void:
	var angle := deg_to_rad(angle_degrees)
	_smear(center, Vector2(0.048, 0.055) * size, angle_degrees, strength * 0.8)
	# Fingers start inside the palm so the print reads as one hand; only the
	# fingertips, pressed hardest, show the ridges of a fingerprint.
	var fingers: Array[Vector2] = [
		Vector2(-0.033, 0.075), Vector2(-0.011, 0.085), Vector2(0.011, 0.082), Vector2(0.032, 0.07),
	]
	for finger in fingers:
		var finger_center := center + (finger * size).rotated(angle)
		_smear(finger_center, Vector2(0.012, 0.038) * size, angle_degrees, strength * 0.85)
		var tip := center + ((finger + Vector2(0.0, 0.028)) * size).rotated(angle)
		_smear(tip, Vector2(0.011, 0.013) * size, angle_degrees, strength, true)
	var thumb := Vector2(-0.06, 0.008)
	_smear(center + (thumb * size).rotated(angle), Vector2(0.013, 0.034) * size, angle_degrees + 35.0, strength * 0.85)


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
