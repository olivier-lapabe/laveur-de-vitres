extends Node3D
## Starting scene: a placeholder storefront at the foot of the tower.
## It only proves that the build pipeline renders a 3D scene on Web and Windows.

const BuildInfo := preload("res://scripts/build_info.gd")

@onready var _camera: Camera3D = $Camera3D
@onready var _sun: DirectionalLight3D = $Sun
@onready var _info: Label = $HUD/Info


func _ready() -> void:
	_sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_camera.look_at(Vector3(0.0, 1.6, 0.0))

	var version := str(ProjectSettings.get_setting("application/config/version", "?"))
	_info.text = "Laveur de vitres — prototype du geste\nVersion %s (%s) · Godot %s" % [
		version,
		BuildInfo.COMMIT,
		Engine.get_version_info().string,
	]
	# CI looks for this line to confirm the scene ran.
	print("Laveur de vitres %s (%s): main scene ready" % [version, BuildInfo.COMMIT])
