extends Node3D
## The street at the foot of the tower, with one dirty bakery window.
## Captures the mouse on click, shows the start overlay while it is free, and
## shows the player's hints while playing.

const BuildInfo := preload("res://scripts/build_info.gd")

@onready var _info: Label = $HUD/Info
@onready var _start_overlay: Control = $HUD/StartOverlay
@onready var _crosshair: Control = $HUD/Crosshair
@onready var _hint: Label = $HUD/Hint
@onready var _player: WindowWasher = $Player


func _ready() -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	_info.text = "Laveur de vitres — prototype du geste\nVersion %s (%s) · Godot %s" % [
		version,
		BuildInfo.COMMIT,
		Engine.get_version_info().string,
	]
	# CI looks for this line to confirm the scene ran.
	print("Laveur de vitres %s (%s): main scene ready" % [version, BuildInfo.COMMIT])


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	# In the browser, Escape releases the mouse without Godot seeing the key.
	var playing := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_start_overlay.visible = not playing
	_crosshair.visible = playing and not _player.is_rubbing()
	_hint.text = _player.hint if playing else ""
