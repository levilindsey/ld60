class_name Part
extends Node2D
## A replacement part from the parts drawers. It rests loose on the
## bench or hidden inside a drawer until the player drags it out.
## Dragging it onto an empty socket fits it; dragging it back over a
## drawer puts it away (docs/design/parts_bin.md). While loose it
## renders over the top of repairables (the z_index in part.tscn);
## once installed it layers with its item.


enum Type {
	GEAR,
	TUBE,
	SPRING,
}

## Seconds the part takes to snap into a socket.
const _FIT_SEC := 0.15
## How many times the part jerks in the "nope" shake.
const _NOPE_SHAKE_STEPS := 4

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


func _ready() -> void:
	DropShadow.attach_silhouette(
		self,
		[get_node("%Art")],
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


## Sets the part's kind and rebuilds its placeholder art.
func setup(part_type: Type) -> void:
	type = part_type
	%Art.polygon = get_polygon(part_type)
	%Art.color = get_color(part_type)


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


## Leaves the hand and snaps into a socket. The socket hears about it
## when the part lands.
func install_into(socket: PartSocket) -> void:
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
		_:
			G.fatal()
			return PackedVector2Array()
