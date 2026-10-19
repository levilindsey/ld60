class_name Part
extends Node2D
## A replacement part from the parts drawers. It rests loose on the
## bench or hidden inside a drawer until the player drags it out.
## Dragging it onto an empty socket fits it; dragging it back over a
## drawer puts it away (docs/design/parts_bin.md). While loose it
## renders over the top of repairables (the z_index in part.tscn);
## once installed it layers with its item. Picking it up and setting
## it down each turn it a bit in the fingers. Fitting it into its
## socket instead turns it to the socket's own orientation.


enum Type {
	GEAR,
	TUBE,
	SPRING,
	TV_CONTROLS,
	LETTER_KEY,
	SPACEBAR,
	LED,
	JOYSTICK,
	CIRCUIT,
}

## Seconds the part takes to snap into a socket.
const _FIT_SEC := 0.15
## How many times the part jerks in the "nope" shake.
const _NOPE_SHAKE_STEPS := 4
## Seconds a pick-up or set-down turn takes.
const _TURN_SEC := 0.25
## How far a pick-up or set-down turn goes, in radians. The least
## still reads as a turn, so every grab and drop moves it a bit.
const _TURN_MIN_RAD := 0.2
const _TURN_MAX_RAD := 0.5
## Real part art per kind, where it exists: the overlay image,
## the piece's region on it, and how long its longer side
## runs on the bench in world pixels. Kinds with no art yet
## keep the placeholder polygon. A new kind gets art by
## adding a row here; nothing else needs to change.
const _ART := {
	Type.TUBE: [
		"res://assets/images/repairables/radio_good_bulb.png",
		Rect2(2118, 1175, 455, 994),
		46.0,
	],
	Type.TV_CONTROLS: [
		"res://assets/images/repairables/tv_controls.png",
		Rect2(2217, 919, 567, 1015),
		46.0,
	],
	Type.LETTER_KEY: [
		"res://assets/images/repairables/keyss_letter_key.png",
		Rect2(1120, 1501, 120, 94),
		36.0,
	],
	Type.SPACEBAR: [
		"res://assets/images/repairables/keyss_spacebar.png",
		Rect2(1296, 1562, 908, 100),
		54.0,
	],
	Type.LED: [
		"res://assets/images/repairables/piano_good_led.png",
		Rect2(227, 718, 418, 110),
		42.0,
	],
	Type.JOYSTICK: [
		"res://assets/images/repairables/atari_joystick_good.png",
		Rect2(1235, 467, 836, 995),
		46.0,
	],
}

@export var type := Type.GEAR

## True once the part sits in its socket. An installed part no longer
## follows the pointer.
var is_installed := false
## True while the part is hidden inside a drawer. It appears when
## that drawer opens.
var is_stored := false
## The drawer the part is stored in, or its last drawer while it is
## out on the bench. -1 when it has never been stored.
var drawer_index := -1
## True while a drawer is putting the part away. A returning part
## cannot be grabbed.
var is_returning := false

var _shake_tween: Tween
var _turn_tween: Tween
var _hint_hint: OutlineHint
var _is_hint_active := false


func _ready() -> void:
	DropShadow.attach_silhouette(
		self,
		[get_node("%Art"), get_node("%Sprite")],
		Vector2(0.0, 6.0),
		func() -> bool:
			return (
				not is_installed
				and not is_stored
				and not is_returning
				and is_instance_valid(G.level)
				and is_instance_valid(G.level.hand)
				and G.level.hand.held != self
			),
		0.8,
	)


## How far the part reaches from its middle, in world pixels.
## The level keeps this much of the part inside the workable
## area when it comes to rest, and it sets how much the part
## bounces and skids when it lands there.
func get_radius_px() -> float:
	var radius := 0.0
	for point in get_polygon(type):
		radius = maxf(radius, point.length())
	return radius


## The level starts bringing this part back to the workable
## area. Until `finish_bench_return()` the part cannot be
## grabbed, which `is_returning` already says for a part on
## its way into a drawer.
func start_bench_return() -> void:
	is_returning = true
	_stop_turn()
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	%Art.position = Vector2.ZERO


## The sound of the part hitting the bench, played by the
## level at its first bounce, not when it comes to rest.
func play_landing_sound() -> void:
	G.audio.play_sound(&"thud")


## The part has come to rest inside the workable area.
func finish_bench_return() -> void:
	is_returning = false
	# A part that is out stays in front of the drawers.
	z_index = 16


## True when this kind has real art (see `_ART`).
static func has_art(part_type: Type) -> bool:
	return _ART.has(part_type)


## Sets the part's kind and its art: the real texture where
## the kind has one, the placeholder polygon where it doesn't.
func setup(part_type: Type) -> void:
	type = part_type
	%Art.polygon = get_polygon(part_type)
	%Art.color = get_color(part_type)
	var sprite := get_node("%Sprite") as Sprite2D
	if _ART.has(part_type):
		var entry: Array = _ART[part_type]
		var region := entry[1] as Rect2
		sprite.texture = load(entry[0] as String) as Texture2D
		sprite.region_enabled = true
		sprite.region_rect = region
		var longer_side := maxf(region.size.x, region.size.y)
		var bench_px := entry[2] as float
		sprite.scale = Vector2.ONE * (bench_px / longer_side)
		sprite.show()
		%Art.hide()
	else:
		sprite.hide()
		%Art.show()


## The wrong socket, or a press that fits nowhere. No penalty.
func nope() -> void:
	G.audio.play_sound(&"clunk")
	G.audio.play_sound(&"hmm_grumpy")
	G.level.hand.show_nope(global_position)
	if is_instance_valid(_shake_tween):
		_shake_tween.kill()
	_shake_tween = create_tween()
	_shake_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	var step_sec := G.settings.nope_shake_sec / (_NOPE_SHAKE_STEPS + 1)
	for step in _NOPE_SHAKE_STEPS:
		var direction := 1.0 if step % 2 == 0 else -1.0
		_shake_tween.tween_property(
			%Art,
			"position",
			Vector2(direction * G.settings.nope_shake_px, 0.0),
			step_sec,
		)
	_shake_tween.tween_property(%Art, "position", Vector2.ZERO, step_sec)


## Shows or hides the idle hint outline around this part, in the
## shape of its kind. The tracker highlights a stored part's drawer
## instead, and this part once it is out on the bench.
func set_hint_active(is_active: bool) -> void:
	_is_hint_active = is_active
	if is_active:
		if not is_instance_valid(_hint_hint):
			_hint_hint = OutlineHint.new()
			add_child(_hint_hint)
			_hint_hint.polygon = get_polygon(type)
		_hint_hint.set_active(true)
	elif is_instance_valid(_hint_hint):
		_hint_hint.set_active(false)


## True while the idle hint outline shows on this part.
func is_hint_active() -> bool:
	return (
		_is_hint_active
		and is_instance_valid(_hint_hint)
		and _hint_hint.is_active()
	)


## The player picked this loose part up, from a drawer or the
## bench. It turns a bit in the fingers.
func on_picked_up() -> void:
	_turn_a_bit()


## The player set this part down on the bench, not into a socket
## or a drawer. It turns a bit as it lands.
func on_set_down() -> void:
	_turn_a_bit()


## Turns the part a little either way, over `_TURN_SEC`. Every
## turn moves at least `_TURN_MIN_RAD`, so it always reads.
func _turn_a_bit() -> void:
	if is_installed:
		return
	_stop_turn()
	var direction := 1.0 if randf() < 0.5 else -1.0
	var target_rotation := (
		rotation
		+ direction * randf_range(_TURN_MIN_RAD, _TURN_MAX_RAD)
	)
	_turn_tween = create_tween()
	_turn_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_turn_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_turn_tween.tween_property(
		self, "rotation", target_rotation, _TURN_SEC
	)


func _stop_turn() -> void:
	if is_instance_valid(_turn_tween):
		_turn_tween.kill()
	_turn_tween = null


## Leaves the hand and snaps into a socket. It turns to the
## socket's own orientation instead of a set-down turn. The
## socket hears about it when the part lands.
func install_into(socket: PartSocket) -> void:
	_stop_turn()
	is_installed = true
	var from_global_position := global_position
	if G.level.hand.held == self:
		G.level.hand.release()
	# Installed, it layers with the item again: the cover can close
	# over it. While held it stays on top (part.tscn's z_index).
	z_index = 0
	z_as_relative = true
	reparent(socket)
	global_position = from_global_position
	reset_physics_interpolation()
	G.audio.play_sound(&"snap")
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		self, "global_position", socket.global_position, _FIT_SEC
	)
	tween.parallel().tween_property(self, "rotation", 0.0, _FIT_SEC)
	tween.tween_callback(socket.on_part_installed)


static func get_display_name(part_type: Type) -> String:
	match part_type:
		Type.GEAR:
			return "Gear"
		Type.TUBE:
			return "Tube"
		Type.SPRING:
			return "Spring"
		Type.TV_CONTROLS:
			return "TV controls"
		Type.LETTER_KEY:
			return "Letter key"
		Type.SPACEBAR:
			return "Spacebar"
		Type.LED:
			return "LED"
		Type.JOYSTICK:
			return "Joystick"
		Type.CIRCUIT:
			return "Circuit"
		_:
			G.fatal()
			return ""


static func get_color(part_type: Type) -> Color:
	match part_type:
		Type.GEAR:
			return Color(0.85, 0.65, 0.2)
		Type.TUBE:
			return Color(0.45, 0.65, 0.85)
		Type.SPRING:
			return Color(0.55, 0.8, 0.5)
		Type.TV_CONTROLS:
			return Color(0.75, 0.45, 0.3)
		Type.LETTER_KEY:
			return Color(0.9, 0.88, 0.8)
		Type.SPACEBAR:
			return Color(0.85, 0.83, 0.75)
		Type.LED:
			return Color(0.95, 0.3, 0.25)
		Type.JOYSTICK:
			return Color(0.8, 0.25, 0.25)
		Type.CIRCUIT:
			return Color(0.25, 0.65, 0.35)
		_:
			G.fatal()
			return Color.WHITE


## A simple shape per kind, about 40 px across. Real art replaces
## these polygons later (LX24).
static func get_polygon(part_type: Type) -> PackedVector2Array:
	match part_type:
		Type.GEAR:
			var points := PackedVector2Array()
			for index in 16:
				var angle := TAU * index / 16.0
				var radius := 19.0 if index % 2 == 0 else 13.5
				points.append(Vector2.from_angle(angle) * radius)
			return points
		Type.TUBE:
			return PackedVector2Array(
				[
					Vector2(-20, -9),
					Vector2(20, -9),
					Vector2(20, 9),
					Vector2(-20, 9),
				]
			)
		Type.SPRING:
			return PackedVector2Array(
				[
					Vector2(-20, 4),
					Vector2(-12, -8),
					Vector2(-4, 4),
					Vector2(4, -8),
					Vector2(12, 4),
					Vector2(20, -8),
					Vector2(20, 2),
					Vector2(12, 14),
					Vector2(4, 2),
					Vector2(-4, 14),
					Vector2(-12, 2),
					Vector2(-20, 14),
				]
			)
		Type.TV_CONTROLS:
			return PackedVector2Array(
				[
					Vector2(-14, -18),
					Vector2(14, -18),
					Vector2(14, 18),
					Vector2(-14, 18),
				]
			)
		Type.LETTER_KEY:
			return PackedVector2Array(
				[
					Vector2(-13, -13),
					Vector2(13, -13),
					Vector2(13, 13),
					Vector2(-13, 13),
				]
			)
		Type.SPACEBAR:
			return PackedVector2Array(
				[
					Vector2(-26, -8),
					Vector2(26, -8),
					Vector2(26, 8),
					Vector2(-26, 8),
				]
			)
		Type.LED:
			var led_points := PackedVector2Array()
			for index in 12:
				var angle := TAU * index / 12.0
				led_points.append(Vector2.from_angle(angle) * 11.0)
			return led_points
		Type.JOYSTICK:
			return PackedVector2Array(
				[
					Vector2(-6, -20),
					Vector2(6, -20),
					Vector2(6, 2),
					Vector2(16, 2),
					Vector2(16, 14),
					Vector2(-16, 14),
					Vector2(-16, 2),
					Vector2(-6, 2),
				]
			)
		Type.CIRCUIT:
			return PackedVector2Array(
				[
					Vector2(-20, -13),
					Vector2(20, -13),
					Vector2(20, 13),
					Vector2(-20, 13),
				]
			)
		_:
			G.fatal()
			return PackedVector2Array()
