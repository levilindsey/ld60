class_name TicketCard
extends Control
## The repair ticket: a paper card in the top-right corner of the screen
## that names the item on the bench and shows the customer's complaint
## (docs/design/outbox.md).
##
## It never takes a mouse press, so the bench under it stays clickable.
## Put it in a CanvasLayer in the level.


## How long the card takes to slide in or out.
@export var slide_sec := 0.35
## How far the card sits off the right edge of the screen while it's away,
## in pixels.
@export var slide_distance_px := 420.0

var _tween: Tween


func _ready() -> void:
	visible = false
	%Slide.position.x = slide_distance_px


## Slides the card in with the item's name and the customer's complaint.
## A card that is still showing swaps its text and slides again.
func show_item(item_name: String, complaint: String) -> void:
	%NameLabel.text = item_name
	%ComplaintLabel.text = complaint
	visible = true
	_slide_to(0.0)


## Slides the card away.
func hide_card() -> void:
	if not visible:
		return
	_slide_to(slide_distance_px)
	_tween.tween_callback(hide)


func _slide_to(target_x: float) -> void:
	if is_instance_valid(_tween):
		_tween.kill()
	# Pausing the game pauses the card with it.
	_tween = create_tween()
	_tween.tween_property(
		%Slide,
		"position:x",
		target_x,
		slide_sec,
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
