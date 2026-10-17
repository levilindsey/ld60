class_name Screw
extends InteractionPoint
## A screw: a FASTENER that holds its layer on until it comes out
## (docs/design/screws.md).
##
## A screw has health. Every slip of its driver costs 1, and at 0 it is
## stripped: the driver no longer bites. A seized screw won't turn until
## the oil can frees it. A screw shows how far in it is by turning its
## head and sliding up out of its hole (`slide`). It never scales.
##
## Each screw type runs its own microgame. It overrides
## `_start_microgame()`, feeds `slide` as it turns the head, and calls
## `remove()` or `install()` once the head has turned all the way.


signal damaged(health: int)
signal stripped
signal removed
signal installed

## The head's look at each health, from the table in screws.md.
enum HeadFrame {
	CLEAN,
	SCRATCHED,
	CHEWED,
	STRIPPED,
}

## How far a loose screw's head sits turned back (counter-clockwise) from
## home: half a turn and a little more. The slot looks the same after half
## a turn, so the player sees a small turned-back angle, and driving the
## screw in turns it about half a turn clockwise.
const LOOSE_TURN_RAD := PI * 1.125

# Placeholder until LX24.
## Tints that stand in for the head frames' art, one per `HeadFrame`.
const _PLACEHOLDER_FRAME_TINTS: Array[Color] = [
	Color(1.0, 1.0, 1.0),
	Color(1.0, 0.85, 0.62),
	Color(0.95, 0.6, 0.38),
	Color(0.6, 0.28, 0.22),
]
## How high the head hops as the screw comes out, and how long it takes.
const _HOP_HEIGHT_PX := 14.0
const _HOP_SEC := 0.25
## Seconds from the grind to the stand-in pry.
const _PRY_DELAY_SEC := 0.3

## The screw head's art. If it is an `AnimatedSprite2D`, its frames are
## the `HeadFrame` states in order.
@export var head: Node2D
## Health when the screw arrives. Each slip costs 1.
@export var max_health := 3
## A rusted screw won't turn until the oil can frees it (LX21).
@export var is_seized := false:
	set(value):
		is_seized = value
		if is_node_ready():
			_update_rust()
## Optional. Rust on the head, shown while seized.
@export var rust_overlay: CanvasItem
## Optional. A rust streak running down from the hole, shown while seized.
@export var rust_streak: CanvasItem

## True once its layer was put back: the screw sits loose in its hole,
## turned back, and driving it in uses the same microgame.
var is_install_mode := false
var health := 0
## How far out of its hole the screw has slid: 0 is home and 1 is all the
## way out. The whole screw, with its head, rust and hit shape, sits
## `G.settings.screw_slide_px` times this far up from home in its parent's
## frame, so the screw node's own rotation doesn't tilt the slide. Set it
## once the screw is ready.
var slide := 0.0:
	set(value):
		slide = clampf(value, 0.0, 1.0)
		_update_slide_position()

## The head's angle when the screw is all the way in.
var _home_head_rotation := 0.0
var _home_head_position := Vector2.ZERO
## Where the screw sits in its parent's frame when `slide` is 0.
var _home_position := Vector2.ZERO
## True once a press on the stripped screw has ground and noped.
var _is_strip_warned := false
## True once the first try on the seized screw has ground as a warning.
var _is_seize_warned := false
var _hop_tween: Tween
var _pry_tween: Tween


func _init() -> void:
	role = Role.FASTENER


func _ready() -> void:
	super._ready()
	G.check(role == Role.FASTENER)
	G.check(is_instance_valid(head))
	G.check(max_health > 0)
	_home_head_rotation = head.rotation
	_home_head_position = head.position
	_home_position = position
	health = max_health
	_update_head_frame()
	_update_rust()


func is_fastened() -> bool:
	if is_install_mode:
		return mode == Mode.FINISHED
	return mode != Mode.FINISHED


func is_stripped() -> bool:
	return health <= 0


## The head frame for the current health: 3 or more is clean, 0 is
## stripped.
func get_head_frame() -> HeadFrame:
	return (
		HeadFrame.STRIPPED - clampi(health, 0, HeadFrame.STRIPPED)
	) as HeadFrame


## Costs health. Each point lost is a SCREW_DAMAGE defect, and the strip
## at 0 adds SCREW_STRIPPED on top.
func take_damage(amount := 1) -> void:
	var lost := mini(amount, health)
	if lost <= 0:
		return
	health -= lost
	for _point in lost:
		_add_defect(RepairQuality.Defect.SCREW_DAMAGE)
	_update_head_frame()
	damaged.emit(health)
	if is_stripped():
		_add_defect(RepairQuality.Defect.SCREW_STRIPPED)
		stripped.emit()


## Frees a seized screw, so it turns normally. The oil can calls it
## (LX21).
func unseize() -> void:
	is_seized = false
	_is_seize_warned = false


## A press with an accepted tool. A stripped or seized screw grinds
## instead of turning, and the tool stays in the hand.
func engage(tool: Tool) -> void:
	if is_stripped():
		_press_stripped(tool)
	elif is_seized:
		_press_seized(tool)
	else:
		super.engage(tool)
		_start_microgame()


## Brings the screw back loose, turned back and slid out, ready to be
## driven in.
func set_install_mode() -> void:
	super.set_install_mode()
	is_install_mode = true
	_stop_hop()
	visible = true
	head.rotation = _home_head_rotation - LOOSE_TURN_RAD
	_snap_slide(1.0)
	if is_stripped():
		# Stand-in until LX19. A pried screw is scrap, and a new one comes
		# from the parts bin. Until then the old one comes back as new.
		health = max_health
		_is_strip_warned = false
		_update_head_frame()


## Takes the screw out: a pop, and it hops off and disappears. It is all
## the way out by then. Its layer and item hear about it from finish().
func remove() -> void:
	G.audio.play_sound("pop")
	slide = 1.0
	finish()
	_hop_off()
	removed.emit()


## Drives the screw home after its layer was put back. The microgame turns
## the head home before it calls this, and the screw ends up all the way
## in.
func install() -> void:
	G.audio.play_sound("click")
	slide = 0.0
	finish()
	installed.emit()


## Starts the microgame once the tool is IN_USE. Each screw type
## overrides it.
func _start_microgame() -> void:
	pass


## The driver no longer bites: a press grinds and nopes. Only the pliers
## work now (LX19).
func _press_stripped(tool: Tool) -> void:
	G.audio.play_sound("grind")
	if not _is_strip_warned:
		_is_strip_warned = true
		tool.nope()
		return
	# Stand-in until LX19. Without the pliers a stripped screw would block
	# the item, so the press after the warning pries it out.
	mode = Mode.ACTIVE
	if is_instance_valid(_pry_tween):
		_pry_tween.kill()
	_pry_tween = create_tween()
	_pry_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_pry_tween.tween_interval(_PRY_DELAY_SEC)
	_pry_tween.tween_callback(_pry)


# Stand-in until LX19.
func _pry() -> void:
	if is_install_mode:
		# It can't come out with its layer on, so it goes in.
		head.rotation = _home_head_rotation
		install()
	else:
		remove()


## A seized screw won't turn. The first try only grinds as a warning, and
## each stalled try after it costs 1 damage.
func _press_seized(tool: Tool) -> void:
	G.audio.play_sound("grind")
	tool.nope()
	if not _is_seize_warned:
		_is_seize_warned = true
		return
	take_damage(1)


func _add_defect(defect: RepairQuality.Defect) -> void:
	var item := get_item()
	if is_instance_valid(item):
		item.quality.add_defect(defect, global_position, self)


func _update_head_frame() -> void:
	var frame := get_head_frame()
	if head is AnimatedSprite2D:
		(head as AnimatedSprite2D).frame = frame
	else:
		# Placeholder until LX24.
		head.modulate = _PLACEHOLDER_FRAME_TINTS[frame]


func _update_rust() -> void:
	# Placeholder until LX24.
	if is_instance_valid(rust_overlay):
		rust_overlay.visible = is_seized
	if is_instance_valid(rust_streak):
		rust_streak.visible = is_seized


## Moves the whole screw to where `slide` says. Home is exact at 0.
func _update_slide_position() -> void:
	if not is_node_ready():
		return
	position = _home_position + Vector2.UP * G.settings.screw_slide_px * slide


## Sets `slide` with no easing from where the screw was, like a screw that
## has just reappeared.
func _snap_slide(fraction: float) -> void:
	slide = fraction
	reset_physics_interpolation()


## The head hops up and fades, then the screw hides. It never scales.
func _hop_off() -> void:
	_stop_hop()
	_hop_tween = create_tween().set_trans(Tween.TRANS_QUAD)
	_hop_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_hop_tween.tween_property(
		head,
		"position:y",
		_home_head_position.y - _HOP_HEIGHT_PX,
		_HOP_SEC,
	).set_ease(Tween.EASE_OUT)
	_hop_tween.parallel().tween_property(
		self,
		"modulate:a",
		0.0,
		_HOP_SEC,
	).set_ease(Tween.EASE_IN)
	_hop_tween.tween_callback(_on_hop_finished)


func _on_hop_finished() -> void:
	visible = false
	_stop_hop()


func _stop_hop() -> void:
	if is_instance_valid(_hop_tween):
		_hop_tween.kill()
	head.position = _home_head_position
	head.reset_physics_interpolation()
	modulate.a = 1.0
