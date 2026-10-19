class_name Exterior
extends Node2D
## The shop's outside, and the title screen: the wall and door
## fill the screen, and the shop name ("Welcome to" / "Fix It" /
## "Come on in") is lettered on the door's sign in Young Serif.
##
## On the enter tap, the door swings open (ExteriorDoor), the
## whole wall scales up toward the door, and wall and door fade
## out after a small delay. Partway through the fade `entered`
## fires, so the shop interior loads underneath the last of it.


signal entered

## The wall and door art. Both are full-canvas overlays of the
## same size; the door image's transparent part shows the wall.
@export var wall_texture: Texture2D
@export var door_texture: Texture2D

## The source art canvas, and where the door and its sign plate
## sit in it, in image pixels (measured from the art).
const _IMAGE_SIZE := Vector2(1754.0, 1240.0)
const _DOOR_IMAGE_RECT := Rect2(535.5, 138, 668.5, 1102)
const _PLATE_IMAGE_RECT := Rect2(712.5, 304.5, 315, 237)
## Where the door's center lands on screen, as a share of the
## viewport. A little low, so the sign sits above middle.
const _DOOR_CENTER_SHARE := Vector2(0.5, 0.55)

const _DOOR_OPEN_SEC := 0.85
const _ENTER_SEC := 1.3
const _ZOOM_SCALE := 1.55
const _FADE_DELAY_SEC := 0.45
const _FADE_SEC := 0.8
## Seconds in, when the interior takes over under the fade.
const _ENTER_AT_SEC := 0.95

var _is_entering := false
var _has_entered := false
var _enter_tween: Tween


func _ready() -> void:
	_layout()


## True while the door is opening and the wall is zooming/fading.
func is_entering() -> bool:
	return _is_entering


## Starts the walk inside. Ignored once it has started.
func enter() -> void:
	if _is_entering or _has_entered:
		return
	_is_entering = true
	G.audio.play_sound(&"creak")
	if is_instance_valid(_enter_tween):
		_enter_tween.kill()
	_enter_tween = create_tween().set_parallel()
	_enter_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_enter_tween.tween_method(
		Callable(self, "_apply_door_open"),
		0.0,
		1.0,
		_DOOR_OPEN_SEC,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_enter_tween.tween_property(
		%Zoom, "scale", Vector2.ONE * _ZOOM_SCALE, _ENTER_SEC
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	# The fade trails the door and the zoom a little.
	_enter_tween.tween_property(
		%Zoom, "modulate:a", 0.0, _FADE_SEC
	).set_delay(_FADE_DELAY_SEC)
	_enter_tween.tween_callback(_emit_entered).set_delay(
		_ENTER_AT_SEC
	)


## Back to the shut door at rest size, fully showing. The HUD
## calls this whenever the title state comes up.
func reset_exterior() -> void:
	if is_instance_valid(_enter_tween):
		_enter_tween.kill()
	_is_entering = false
	_has_entered = false
	%Zoom.scale = Vector2.ONE
	%Zoom.modulate.a = 1.0
	_apply_door_open(0.0)


func _emit_entered() -> void:
	if _has_entered:
		return
	_has_entered = true
	_is_entering = false
	entered.emit()


func _apply_door_open(amount: float) -> void:
	%Door.set_open_amount(amount)


## Fits the wall over the viewport and puts the door, and the
## sign lettering over its plate, where the art says they are.
func _layout() -> void:
	var viewport_size := get_viewport_rect().size
	var image_scale := maxf(
		viewport_size.x / _IMAGE_SIZE.x,
		viewport_size.y / _IMAGE_SIZE.y,
	)
	var door_center := _DOOR_CENTER_SHARE * viewport_size
	var wall_origin := (
		door_center - _DOOR_IMAGE_RECT.get_center() * image_scale
	)
	%Zoom.position = door_center

	%Wall.position = wall_origin - door_center
	%Wall.scale = Vector2.ONE * image_scale
	%Wall.texture = wall_texture

	%Door.position = (
		wall_origin + _DOOR_IMAGE_RECT.position * image_scale
		- door_center
	)
	%Door.texture = door_texture
	%Door.source_rect = _DOOR_IMAGE_RECT
	%Door.door_size = _DOOR_IMAGE_RECT.size * image_scale
	%Door.set_open_amount(0.0)

	# The lettering renders into the sign viewport at plate
	# resolution; the door slice-draws it with the face.
	%Door.sign_texture = %SignViewport.get_texture()
	%Door.sign_rect = Rect2(
		(_PLATE_IMAGE_RECT.position - _DOOR_IMAGE_RECT.position)
		* image_scale,
		_PLATE_IMAGE_RECT.size * image_scale,
	)
	var plate_size := Vector2(%SignViewport.size)
	_fit_sign_font(%SignWelcome, plate_size, 0.15)
	_fit_sign_font(%SignTitle, plate_size, 0.34)
	_fit_sign_font(%SignSub, plate_size, 0.17)


## Sizes a sign label's font to its plate: as tall as the given
## share of the plate, and never wider than the plate.
func _fit_sign_font(
	label: Label, plate_size: Vector2, height_share: float
) -> void:
	var font := label.get_theme_font("font")
	var font_size := int(plate_size.y * height_share)
	if is_instance_valid(font):
		var text_width := font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
		).x
		if text_width > plate_size.x * 0.92:
			font_size = int(
				font_size * plate_size.x * 0.92 / text_width
			)
	label.add_theme_font_size_override(
		"font_size", maxi(font_size, 8)
	)
