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
@export var hand_reach := 1.1
## How far the player can spit, in meters.
@export var spit_reach := 2.5

## Mouse movement is ignored for this long and this many frames after the mouse
## gets captured: browsers can report one huge jump when the pointer locks.
const CAPTURE_SETTLE_MSEC := 150
const CAPTURE_SETTLE_FRAMES := 3
## Longest mouse movement taken from a single event, in pixels, so that one
## bogus event cannot spin the view.
const MAX_MOUSE_STEP := 120.0
## Distance between two rubs along a stroke, in meters.
const RUB_STEP := 0.02
## Above this hand dirt, the hand smears more grease than it removes.
const DIRTY_HAND := 0.6
## Hand dirt wiped off per second while wiping.
const WIPE_SPEED := 0.8
const SPIT_COOLDOWN_MSEC := 500
## Gap kept between the palm and the glass, in meters.
const PALM_GAP := 0.018
const SKIN_COLOR := Color(0.72, 0.52, 0.41)
const GRIME_COLOR := Color(0.33, 0.28, 0.2)

## How dirty the hands are, from 0 (clean) to 1 (covered in grease).
var hand_dirt := 0.0
## A short instruction for the HUD, depending on what the player can do.
var hint := ""

## When the mouse got captured, or -1 while it is free.
var _captured_since_msec := -1
var _captured_since_frame := -1
var _rubbing := false
## Screen position of the rubbing hand, moved by the mouse while rubbing.
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
@onready var _skin := ($Head/Camera3D/RightHand/Palm as MeshInstance3D).mesh.get("material") as StandardMaterial3D


func is_rubbing() -> bool:
	return _rubbing


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
	var relative := motion.relative.limit_length(MAX_MOUSE_STEP)
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
	var hit := _glass_hit(_screen_center())
	if hit.is_empty() or hit.distance > hand_reach:
		return
	_rubbing = true
	_rub_cursor = _screen_center()
	_on_glass = false
	_touch(hit.point)


func _stop_rubbing() -> void:
	_rubbing = false
	_on_glass = false


## While rubbing, the mouse moves the hand across the glass.
func _move_hand(relative: Vector2) -> void:
	_rub_cursor = (_rub_cursor + relative).clamp(Vector2.ZERO, get_viewport().get_visible_rect().size)
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
			hand_dirt = clampf(hand_dirt + glass.rub(glass.uv_at(at), stroke.length() / steps, hand_dirt), 0.0, 1.0)
	_last_rub_point = point
	_on_glass = true
	_hand_target = point + glass.get_normal() * PALM_GAP


func _spit() -> void:
	if _rubbing or Time.get_ticks_msec() < _spit_ready_msec:
		return
	var hit := _glass_hit(_screen_center())
	if hit.is_empty() or hit.distance > spit_reach:
		return
	glass.spit(hit.uv)
	_spit_ready_msec = Time.get_ticks_msec() + SPIT_COOLDOWN_MSEC


func _update_hands(delta: float) -> void:
	_skin.albedo_color = SKIN_COLOR.lerp(GRIME_COLOR, hand_dirt * 0.85)
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
		hint = "Bougez la souris pour frotter · relâchez le clic pour lâcher la vitre"
	elif hand_dirt >= DIRTY_HAND:
		hint = "Vos mains sont sales : elles étalent la graisse. Maintenez E pour les essuyer"
	else:
		var hit := _glass_hit(_screen_center())
		if hit.is_empty():
			hint = ""
		elif hit.distance > hand_reach:
			hint = "Clic droit : cracher · approchez-vous pour frotter"
		else:
			hint = "Clic droit : cracher · maintenez le clic gauche pour frotter"


func _screen_center() -> Vector2:
	return get_viewport().get_visible_rect().size / 2.0


func _glass_hit(screen_position: Vector2) -> Dictionary:
	if glass == null:
		return {}
	return glass.intersect(_camera.project_ray_origin(screen_position), _camera.project_ray_normal(screen_position))
