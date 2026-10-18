class_name PartsBin
extends Node2D
## The parts drawer: a fixed space in the upper-left that opens the
## parts menu, and takes parts back (docs/design/parts_bin.md).


## The parts the menu offers. Taking one never runs the drawer out.
const _CATALOG: Array[Part.Type] = [
	Part.Type.GEAR,
	Part.Type.TUBE,
	Part.Type.SPRING,
]

const _DRAWER_COLOR := Color(0.35, 0.25, 0.15, 0.9)
const _RETURN_COLOR := Color(0.6, 0.45, 0.2, 0.95)

## The scene a taken part comes from.
@export var part_scene: PackedScene

var _is_return_hint_shown := false


func _ready() -> void:
	G.check(is_instance_valid(part_scene))
	G.level.get_parts_menu().part_selected.connect(_on_part_selected)


func _physics_process(_delta: float) -> void:
	var show_hint := (
		is_instance_valid(G.level)
		and G.level.hand.held is Part
	)
	if show_hint == _is_return_hint_shown:
		return
	_is_return_hint_shown = show_hint
	%Label.text = "RETURN" if show_hint else "PARTS"
	%Art.color = _RETURN_COLOR if show_hint else _DRAWER_COLOR


## The drawer's center on screen, where menu copies fly from.
func get_screen_position() -> Vector2:
	return get_canvas_transform() * global_position


## Opens the parts menu out of the drawer.
func open_menu() -> void:
	G.audio.play_sound(&"whoosh")
	G.level.get_parts_menu().open_menu(_CATALOG, get_screen_position())


## A held part comes back: it flies to the drawer and is gone.
func take_back(part: Part) -> void:
	part.fly_home(global_position)


func _on_part_selected(part_type: Part.Type) -> void:
	var part := part_scene.instantiate() as Part
	G.check(is_instance_valid(part))
	G.level.add_child(part)
	part.setup(part_type)
	part.global_position = G.level.hand.pointer_position
	G.level.hand.grab(part)
	G.audio.play_sound(&"click")
