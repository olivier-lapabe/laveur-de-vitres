extends Node3D
## First-person walker: looks around with the mouse and takes a few steps along
## the sidewalk with ZQSD/WASD (same physical keys) or the arrow keys.

## Calm walking pace, in meters per second.
@export var walk_speed := 1.6
## Radians of rotation per pixel of mouse movement.
@export var mouse_sensitivity := 0.0025
## The part of the sidewalk the player can walk on (x and z only).
@export var walk_area := Rect2(-6.0, 1.4, 12.0, 4.1)

@onready var _head: Node3D = $Head


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	rotate_y(-motion.relative.x * mouse_sensitivity)
	_head.rotate_x(-motion.relative.y * mouse_sensitivity)
	_head.rotation.x = clampf(_head.rotation.x, deg_to_rad(-85.0), deg_to_rad(85.0))


func _process(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var step := global_transform.basis * Vector3(input.x, 0.0, input.y)
	step.y = 0.0
	position += step.limit_length(1.0) * walk_speed * delta
	position.x = clampf(position.x, walk_area.position.x, walk_area.end.x)
	position.z = clampf(position.z, walk_area.position.y, walk_area.end.y)
