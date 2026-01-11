extends Node3D


@onready var _rotation_deg : float = 45

@export var _auto_rotate : bool = true

var _is_rotating : bool = false
var _tween : Tween


func _process(delta: float) -> void:
	if _auto_rotate:
		rotate_y(deg_to_rad(15) * delta)


func _input(event: InputEvent) -> void:
	if _is_rotating:
		return
	
	if event.is_action_pressed("rotate_camera_left"):
		_is_rotating = true
		await _rotate_camera(-_rotation_deg)
		_is_rotating = false
	elif event.is_action_pressed("rotate_camera_right"):
		_is_rotating = true
		await _rotate_camera(_rotation_deg)
		_is_rotating = false


func _rotate_camera(degrees: float) -> Signal:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	var new_rotation_y = rotation.y + deg_to_rad(degrees)
	_tween.tween_property(self, "rotation:y", new_rotation_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return _tween.finished
