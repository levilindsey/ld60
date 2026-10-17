class_name Screw
extends InteractionPoint
## A screw: a FASTENER that holds its layer on until it comes out.
##
## Only the remove and install states the layers need are here. Health,
## stripping and seizing come with LX10 (docs/design/screws.md). A screw
## shows how far in it is by turning its head. It never scales.


signal removed
signal installed

## How far a loose screw's head sits turned back (counter-clockwise) from
## home: half a turn and a little more. The slot looks the same after half
## a turn, so the player sees a small turned-back angle, and driving the
## screw in turns it about half a turn clockwise.
const LOOSE_TURN_RAD := PI * 1.125

## The screw head's art.
@export var head: Node2D

## True once its layer was put back: the screw sits loose in its hole,
## turned back, and driving it in uses the same microgame.
var is_install_mode := false

## The head's angle when the screw is all the way in.
var _home_head_rotation := 0.0


func _init() -> void:
	role = Role.FASTENER


func _ready() -> void:
	super._ready()
	G.check(role == Role.FASTENER)
	G.check(is_instance_valid(head))
	_home_head_rotation = head.rotation


func is_fastened() -> bool:
	if is_install_mode:
		return mode == Mode.FINISHED
	return mode != Mode.FINISHED


## Brings the screw back loose and turned back, ready to be driven in.
func set_install_mode() -> void:
	is_install_mode = true
	mode = Mode.UNSTARTED
	visible = true
	head.rotation = _home_head_rotation - LOOSE_TURN_RAD


## Takes the screw out. Its layer and item hear about it from finish().
func remove() -> void:
	visible = false
	G.audio.play_sound("pop")
	finish()
	removed.emit()


## Drives the screw home after its layer was put back. The microgame turns
## the head home before it calls this.
func install() -> void:
	G.audio.play_sound("click")
	finish()
	installed.emit()
