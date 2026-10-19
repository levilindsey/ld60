class_name ShrinkRay
extends Repairable
## A raygun from the pawn shop.
##
## The first hammer hit anywhere on it sets it off: a beam from the crystal
## shrinks the hammer for good (`Hammer.shrink()`). After that, the jammed
## spot (`%Jam`) takes a few tiny-hammer hits, the grime on the crystal
## wipes off, and the cracked crystal and the spring in the hook get
## replaced.


const _BEAM_SEC := 0.4
const _BEAM_WIDTH_PX := 12.0
const _BEAM_COLOR := Color(1.0, 0.35, 0.95)
## How far the beam's zigzag strays from a straight line, in pixels.
const _BEAM_JITTER_PX := 6.0
## How long each zigzag segment of the beam is, in pixels.
const _BEAM_STEP_PX := 18.0
## Above the hand and the tools.
const _BEAM_Z_INDEX := 40


## True once the ray has gone off.
var has_fired := false


func _ready() -> void:
	super()
	%Jam.visible = false
	add_to_group(Hammer.STRIKABLE_PROPS_GROUP)


## True for a hammer press on the ray's drawing before it has gone off.
func is_struck_at(global_point: Vector2) -> bool:
	var art := layers[0].art as Sprite2D
	return (
		not has_fired
		and mode == Mode.UNDER_REPAIR
		and art.is_pixel_opaque(art.to_local(global_point))
	)


## The hammer set it off: the beam shrinks the hammer, and the jammed spot
## shows up.
func on_struck(_charge: float) -> void:
	has_fired = true
	%Jam.visible = true
	G.audio.play_sound(&"thud", true)
	G.audio.play_sound(&"zap", true)
	G.level.shake_camera(8.0, 0.25)
	var hammer := G.level.hand.get_held_tool() as Hammer
	if is_instance_valid(hammer):
		_draw_beam(hammer.get_work_end_position())
		hammer.shrink()


## A crackling beam from the crystal to the target that fades out.
func _draw_beam(target_global_position: Vector2) -> void:
	var beam := Line2D.new()
	beam.width = _BEAM_WIDTH_PX
	beam.default_color = _BEAM_COLOR
	beam.joint_mode = Line2D.LINE_JOINT_ROUND
	beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
	beam.end_cap_mode = Line2D.LINE_CAP_ROUND
	beam.z_index = _BEAM_Z_INDEX
	G.level.add_child(beam)
	var start := %Crystal.global_position as Vector2
	var step_count := maxi(
		ceili(start.distance_to(target_global_position) / _BEAM_STEP_PX),
		1,
	)
	var normal := (target_global_position - start).orthogonal().normalized()
	for step in step_count + 1:
		var point := start.lerp(
			target_global_position,
			float(step) / step_count,
		)
		if step > 0 and step < step_count:
			point += normal * randf_range(-_BEAM_JITTER_PX, _BEAM_JITTER_PX)
		beam.add_point(beam.to_local(point))
	var tween := beam.create_tween()
	tween.set_parallel()
	tween.tween_property(beam, "modulate:a", 0.0, _BEAM_SEC)
	tween.tween_property(beam, "width", _BEAM_WIDTH_PX * 0.3, _BEAM_SEC)
	tween.chain().tween_callback(beam.queue_free)
