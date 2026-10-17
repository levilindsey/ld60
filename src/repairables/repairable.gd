class_name Repairable
extends Node2D


enum Type {
	TEST_FLAT_HEAD_SCREW_REPAIRABLE,
}

enum Mode {
	ENTERING,
	LEAVING,
	UNDER_REPAIR,
}

const ROTATE_DURATION_SEC := 0.3
const POSITION_DURATION_SEC := 0.3

const ROTATION_OFFSET_MAX := PI * 0.1

var mode := Mode.ENTERING

@onready var position_tween: Tween
@onready var rotation_tween: Tween


func tween_rotation(p_rotation: float, ease := Tween.EASE_IN_OUT) -> void:
	if is_instance_valid(rotation_tween):
		rotation_tween.kill()
	rotation_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	rotation_tween.tween_property(self, "rotation", p_rotation, ROTATE_DURATION_SEC)


func tween_position(p_global_position: Vector2, ease := Tween.EASE_IN_OUT) -> void:
	if is_instance_valid(position_tween):
		position_tween.kill()
	position_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(ease)
	position_tween.tween_property(self, "global_position", p_global_position, POSITION_DURATION_SEC)
