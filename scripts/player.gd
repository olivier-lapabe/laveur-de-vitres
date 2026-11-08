class_name WindowWasher
extends Node3D
## The player, in first person: looks around, walks along the sidewalk, spits
## on the glass and rubs it with bare hands.
##
## Mouse: look around. ZQSD/WASD (same physical keys) or arrows: walk.
## Hold the left button on the glass to rub: the camera stays still and the
## mouse moves the hand on the glass. Right button: spit. Hold E: wipe the hands.

## Calm walking pace, in meters per second.
@export var walk_speed := 1.6
## Radians of rotation per pixel of mouse movement.
@export var mouse_sensitivity := 0.0025
## The part of the sidewalk the player can walk on (x and z only).
@export var walk_area := Rect2(-6.0, 1.4, 12.0, 4.1)
## The glass to wash.
@export var glass: DirtyGlass
## How far a hand reaches from the eyes, in meters.
@export var hand_reach := 1.6
## How far the player can spit, in meters.
@export var spit_reach := 2.5

## Mouse movement is ignored for this long and this many frames after the mouse
## gets captured: browsers can report one huge jump when the pointer locks.
const CAPTURE_SETTLE_MSEC := 150
const CAPTURE_SETTLE_FRAMES := 3
## Mouse events longer than this, in pixels, are dropped: browsers sometimes
## report the pointer jumping to a screen corner, which no hand does in a frame.
const MAX_MOUSE_STEP := 250.0
## Distance between two rubs along a stroke, in meters.
const RUB_STEP := 0.02
## Above this hand dirt, the hand smears more dirt than it removes.
const DIRTY_HAND := 0.6
## Seconds for wet hands to dry in the air.
const HAND_DRY_SECONDS := 10.0
## Share of the hands' water given to dry glass per meter of rubbing.
const HAND_WATER_PER_METER := 0.3
## Hand dirt (and water) wiped off per second while wiping.
const WIPE_SPEED := 0.8
const SPIT_COOLDOWN_MSEC := 500
## Gap kept between the palm and the glass, in meters.
const PALM_GAP := 0.018

## How dirty the hands are, from 0 (clean) to 1 (covered in dirt).
var hand_dirt := 0.0
## How wet the hands are, from 0 (dry) to 1: rubbing wet glass wets them, and
## wet hands clean faster anywhere.
var hand_wet := 0.0
## A short instruction for the HUD, depending on what the player can do.
var hint := ""

## When the mouse got captured, or -1 while it is free.
var _captured_since_msec := -1
var _captured_since_frame := -1
var _rubbing := false
## Where the rubbing hand is on screen, moved by the mouse while rubbing:
## (0, 0) is the crosshair, (±1, ±1) the screen corners.
var _rub_cursor := Vector2.ZERO
var _on_glass := false
var _last_rub_point := Vector3.ZERO
var _hand_target := Vector3.ZERO
var _spit_ready_msec := 0
var _wiping := false

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _right_hand: Node3D = $Head/Camera3D/RightHand
@onready var _left_hand: Node3D = $Head/Camera3D/LeftHand
@onready var _right_rest := _right_hand.transform
@onready var _left_rest := _left_hand.transform
## Both hands share this material, so tinting it dirties both.
@onready var _skin := ($Head/Camera3D/RightHand/Palm as MeshInstance3D).mesh.get("material") as ShaderMaterial


## Where the player aims at the glass in the world, or null; for the F3 marker.
func aim_point() -> Variant:
	var hit := _glass_hit(_rub_cursor if _rubbing else Vector2.ZERO)
	return null if hit.is_empty() else hit.point


func is_rubbing() -> bool:
	return _rubbing


## Live values for the F3 debug panel (in French, for the PO's playtests).
func debug_text() -> String:
	var text := "Saleté des mains : %d %%\nMains humides : %d %%" % [roundi(hand_dirt * 100.0), roundi(hand_wet * 100.0)]
	var hit := _glass_hit(_rub_cursor if _rubbing else Vector2.ZERO)
	if hit.is_empty():
		return text + "\nVitre : pas visée"
	var uv: Vector2 = hit.uv
	var on_screen := _camera.unproject_position(hit.point)
	text += "\nVisée à l'écran : (%d, %d) · vue %s · fenêtre %s · caméra %s" % [
		on_screen.x, on_screen.y,
		get_viewport().get_visible_rect().size,
		DisplayServer.window_get_size(),
		_camera.get_viewport().size,
	]
	return text + "\nDistance à la vitre : %.2f m%s\nHumidité ici : %d %%\nSaleté ici : %d %%" % [
		hit.distance,
		"" if hit.distance <= hand_reach else " (trop loin pour frotter)",
		roundi(glass.wetness_at(uv) * 100.0),
		roundi(glass.dirt_at(uv) * 100.0),
	]


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_start_rubbing()
			else:
				_stop_rubbing()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			_spit()
		return
	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if not _capture_settled():
		return
	if motion.relative.length() > MAX_MOUSE_STEP:
		return
	var relative := motion.relative
	if _rubbing:
		_move_hand(relative)
	else:
		rotate_y(-relative.x * mouse_sensitivity)
		_head.rotate_x(-relative.y * mouse_sensitivity)
		_head.rotation.x = clampf(_head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_captured_since_msec = -1
		_captured_since_frame = -1
		_stop_rubbing()
		_wiping = false
		hint = ""
		_update_hands(delta)
		return
	if _captured_since_msec < 0:
		_captured_since_msec = Time.get_ticks_msec()
		_captured_since_frame = Engine.get_process_frames()

	_wiping = Input.is_action_pressed("wipe_hands") and not _rubbing
	if _wiping:
		hand_dirt = maxf(0.0, hand_dirt - WIPE_SPEED * delta)
		hand_wet = maxf(0.0, hand_wet - WIPE_SPEED * delta)
	hand_wet = maxf(0.0, hand_wet - delta / HAND_DRY_SECONDS)
	if not _rubbing and not _wiping:
		_walk(delta)
	_update_hands(delta)
	_update_hint()


func _capture_settled() -> bool:
	return (_captured_since_msec >= 0
		and Time.get_ticks_msec() - _captured_since_msec >= CAPTURE_SETTLE_MSEC
		and Engine.get_process_frames() - _captured_since_frame >= CAPTURE_SETTLE_FRAMES)


func _walk(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var step := global_transform.basis * Vector3(input.x, 0.0, input.y)
	step.y = 0.0
	position += step.limit_length(1.0) * walk_speed * delta
	position.x = clampf(position.x, walk_area.position.x, walk_area.end.x)
	position.z = clampf(position.z, walk_area.position.y, walk_area.end.y)


func _start_rubbing() -> void:
	var hit := _glass_hit(Vector2.ZERO)
	if hit.is_empty() or hit.distance > hand_reach:
		return
	_rubbing = true
	_rub_cursor = Vector2.ZERO
	_on_glass = false
	_touch(hit.point)


func _stop_rubbing() -> void:
	_rubbing = false
	_on_glass = false


## While rubbing, the mouse moves the hand across the glass.
func _move_hand(relative: Vector2) -> void:
	var half_screen := get_viewport().get_visible_rect().size / 2.0
	_rub_cursor = (_rub_cursor + Vector2(relative.x, -relative.y) / half_screen).clamp(-Vector2.ONE, Vector2.ONE)
	var hit := _glass_hit(_rub_cursor)
	if hit.is_empty() or hit.distance > hand_reach:
		_on_glass = false
		return
	_touch(hit.point)


## Puts the palm on the glass at point, rubbing along the way from the last point.
func _touch(point: Vector3) -> void:
	if _on_glass:
		var stroke := point - _last_rub_point
		var steps := maxi(1, ceili(stroke.length() / RUB_STEP))
		for i in steps:
			var at := _last_rub_point + stroke * (float(i + 1) / steps)
			var uv := glass.uv_at(at)
			var step_length := stroke.length() / steps
			hand_dirt = clampf(hand_dirt + glass.rub(uv, step_length, hand_dirt, hand_wet), 0.0, 1.0)
			# Wet glass wets the hand; dry glass soaks up what the hand carries.
			hand_wet = maxf(hand_wet - step_length * HAND_WATER_PER_METER, glass.wetness_at(uv))
	_last_rub_point = point
	_on_glass = true
	_hand_target = point + glass.get_normal() * PALM_GAP


func _spit() -> void:
	if _rubbing or Time.get_ticks_msec() < _spit_ready_msec:
		return
	var hit := _glass_hit(Vector2.ZERO)
	if hit.is_empty() or hit.distance > spit_reach:
		return
	glass.spit(hit.uv)
	_spit_ready_msec = Time.get_ticks_msec() + SPIT_COOLDOWN_MSEC


func _update_hands(delta: float) -> void:
	_skin.set_shader_parameter("dirt", hand_dirt)
	_skin.set_shader_parameter("wet", hand_wet)
	var weight := clampf(delta * 14.0, 0.0, 1.0)
	if _rubbing and _on_glass:
		# Palm flat against the glass, fingers up.
		_right_hand.global_position = _right_hand.global_position.lerp(_hand_target, clampf(delta * 30.0, 0.0, 1.0))
		_right_hand.global_transform.basis = Basis.looking_at(-glass.get_normal(), Vector3.UP)
	else:
		_right_hand.transform = _right_hand.transform.interpolate_with(_rest_pose(_right_rest, 1.0), weight)
	# The left hand is mirrored (negative scale): move it without blending its rotation.
	_left_hand.position = _left_hand.position.lerp(_rest_pose(_left_rest, -1.0).origin, weight)


## The resting pose of a hand, lowered to the overalls while wiping.
func _rest_pose(rest: Transform3D, side: float) -> Transform3D:
	if not _wiping:
		return rest
	var t := Time.get_ticks_msec() / 1000.0
	return rest.translated(Vector3(0.0, -0.2 + 0.04 * sin(t * 18.0 + side), 0.05))


func _update_hint() -> void:
	if _rubbing:
		if hand_dirt >= DIRTY_HAND:
			hint = "Vos mains sont sales : elles étalent la saleté. Lâchez et maintenez E pour les essuyer"
		elif glass.last_rub_was_dry:
			hint = "À sec, ça part lentement : crachez (clic droit) pour mouiller la vitre et vos mains"
		else:
			hint = "Bougez la souris pour frotter · relâchez le clic pour lâcher la vitre"
	elif hand_dirt >= DIRTY_HAND:
		hint = "Vos mains sont sales : elles étalent la saleté. Maintenez E pour les essuyer"
	else:
		var hit := _glass_hit(Vector2.ZERO)
		if hit.is_empty():
			hint = ""
		elif hit.distance > hand_reach:
			hint = "Clic droit : cracher · approchez-vous pour frotter"
		else:
			hint = "Clic droit : cracher · maintenez le clic gauche pour frotter"


## The glass under a point of the screen, from (0, 0) at the crosshair to
## (±1, ±1) at the corners (y up). The ray is built from the camera's own
## direction and field of view: in the browser, the camera's notion of screen
## pixels does not always match the viewport's, which put the spit off target.
func _glass_hit(screen_point: Vector2) -> Dictionary:
	if glass == null:
		return {}
	var size := get_viewport().get_visible_rect().size
	var half_height := tan(deg_to_rad(_camera.fov) / 2.0)
	var half_width := half_height * size.x / maxf(size.y, 1.0)
	var camera_basis := _camera.global_transform.basis
	var direction := (camera_basis * Vector3(screen_point.x * half_width, screen_point.y * half_height, -1.0)).normalized()
	return glass.intersect(_camera.global_position, direction)
