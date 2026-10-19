class_name BirdController
extends Node
## Bread the bird. Once the player has got
## `REPAIRABLES_BEFORE_SMACK` repairables through the outbox, the
## bird smacks into the window `SMACK_DELAY_SEC` seconds into the
## next repairable. From then on it peeks out of the tree every
## so often for the rest of the session; it never peeks before
## the smack. The two animations are the `%BirdSmack` and
## `%BirdPeak` scene instances under the background's Scaler.


const REPAIRABLES_BEFORE_SMACK := 2
const SMACK_DELAY_SEC := 4.0
## Seconds into the smack animation when the bird reaches the
## glass (about frame 26 of 41 at 15 fps): the smack and caw
## sounds land there.
const SMACK_HIT_SEC := 1.7
const PEAK_INTERVAL_MIN_SEC := 20.0
const PEAK_INTERVAL_MAX_SEC := 45.0

var _completed_count := 0
var _has_smacked := false
var _item: Repairable


func _ready() -> void:
	(%BirdSmack.get_node("AnimatedSprite2D") as AnimatedSprite2D) \
		.animation_finished.connect(_on_smack_finished)
	(%BirdPeak.get_node("AnimatedSprite2D") as AnimatedSprite2D) \
		.animation_finished.connect(_on_peak_finished)


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(G.level):
		return
	var item := G.level.active_repairable
	if item == _item:
		return
	_item = item
	if not is_instance_valid(item):
		return
	item.landed.connect(_on_item_landed, CONNECT_ONE_SHOT)
	item.departed.connect(_on_item_departed, CONNECT_ONE_SHOT)


## A repairable went out the outbox: one more got through. Once
## enough are through, the next landing arms the smack.
func _on_item_departed() -> void:
	_completed_count += 1


func _on_item_landed() -> void:
	if _has_smacked or _completed_count < REPAIRABLES_BEFORE_SMACK:
		return
	G.time.set_timeout(_play_smack, SMACK_DELAY_SEC)


func _play_smack() -> void:
	if _has_smacked:
		return
	_has_smacked = true
	var root := %BirdSmack as Node2D
	root.show()
	(root.get_node("AnimatedSprite2D") as AnimatedSprite2D).play(
		&"smack"
	)
	G.time.set_timeout(_play_smack_hit, SMACK_HIT_SEC)


func _play_smack_hit() -> void:
	G.audio.play_sound(&"window_smack")
	G.audio.play_sound(&"caw")


func _on_smack_finished() -> void:
	(%BirdSmack as Node2D).hide()
	_roll_next_peak()


## Waits a fresh random interval, then peeks. Re-rolled after
## every peek, so no two gaps are alike.
func _roll_next_peak() -> void:
	G.time.set_timeout(
		_play_peak,
		randf_range(PEAK_INTERVAL_MIN_SEC, PEAK_INTERVAL_MAX_SEC),
	)


func _play_peak() -> void:
	var root := %BirdPeak as Node2D
	root.show()
	(root.get_node("AnimatedSprite2D") as AnimatedSprite2D).play(
		&"peak"
	)


func _on_peak_finished() -> void:
	(%BirdPeak as Node2D).hide()
	_roll_next_peak()
