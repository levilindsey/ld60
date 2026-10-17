class_name DefectPopup
extends Node2D
## A small "-N" that floats up from a defect and fades out, so the player
## learns what cost them points.
##
## Spawn one with `DefectPopup.spawn(parent, points, global_position)`. See
## docs/design/quality.md.


const _GROUP := &"defect_popups"

## How long the number takes to rise and fade out.
@export var duration_sec := 1.0
## How far the number rises, in world pixels.
@export var rise_px := 36.0
## How much bigger the number is when it first appears.
@export var pop_scale := 1.5
## How long the number takes to settle to its normal size.
@export var pop_sec := 0.15
## Numbers that appear close together are stacked, so each stays readable.
## This is how close "close" is, in world pixels.
@export var stack_radius_px := 24.0
## This is how soon after the first number another one gets stacked on it.
@export var stack_window_sec := 0.5
## This is how far each number in a stack is raised above the last one.
@export var stack_spacing_px := 26.0

var _origin := Vector2.ZERO
var _spawn_time_msec := 0


## Shows a "-N" at a world position and frees itself a moment later. The
## parent can be any node in the level.
static func spawn(
	parent: Node,
	points: int,
	world_position: Vector2,
) -> DefectPopup:
	var popup := G.settings.defect_popup_scene.instantiate() as DefectPopup
	parent.add_child(popup)
	popup.show_points(points, world_position)
	return popup


func show_points(points: int, p_global_position: Vector2) -> void:
	%Label.text = "-%d" % absi(points)
	_origin = p_global_position
	_spawn_time_msec = Time.get_ticks_msec()
	add_to_group(_GROUP)

	var stack_index := _count_stacked_popups()
	global_position = (
		p_global_position
		+ Vector2(0.0, -stack_index * stack_spacing_px)
	)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(
		self,
		"global_position:y",
		global_position.y - rise_px,
		duration_sec,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self,
		"scale",
		Vector2.ONE,
		pop_sec,
	).from(Vector2.ONE * pop_scale).set_trans(Tween.TRANS_BACK)
	tween.tween_property(
		self,
		"modulate:a",
		0.0,
		duration_sec * 0.4,
	).set_delay(duration_sec * 0.6)
	tween.chain().tween_callback(queue_free)


## How many live numbers are already showing at this spot, which this one
## should stack above.
func _count_stacked_popups() -> int:
	var stack_count := 0
	var radius_squared := stack_radius_px * stack_radius_px
	var window_msec := int(stack_window_sec * 1000.0)
	for node in get_tree().get_nodes_in_group(_GROUP):
		var other := node as DefectPopup
		if other == self:
			continue
		var is_recent := (
			_spawn_time_msec - other._spawn_time_msec <= window_msec
		)
		var is_near := (
			_origin.distance_squared_to(other._origin) <= radius_squared
		)
		if is_recent and is_near:
			stack_count += 1
	return stack_count
