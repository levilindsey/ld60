class_name HammerReticle
extends Node2D
## The hammer's crosshair and strength ring (docs/design/
## hammer.md). It draws above the hammer head, at the locked
## strike point, while a swing winds up.


func _process(_delta: float) -> void:
	queue_redraw()


## Where the crosshair sits, in this node's drawing space: the
## hammer's working end, not the hammer's origin.
func get_center() -> Vector2:
	var hammer := get_parent() as Hammer
	if not is_instance_valid(hammer):
		return Vector2.ZERO
	return to_local(hammer.get_work_end_position())


func _draw() -> void:
	var hammer := get_parent() as Hammer
	if not is_instance_valid(hammer) or not hammer.is_winding():
		return
	var radius := G.settings.hammer_reticle_radius_px
	if is_instance_valid(G.level) and G.level.hand.is_touch:
		radius = G.settings.hammer_reticle_radius_touch_px
	var start := -PI * 0.5
	var center := get_center()
	draw_line(
		center + Vector2(-8, 0), center + Vector2(8, 0), Color.WHITE, 2.0
	)
	draw_line(
		center + Vector2(0, -8), center + Vector2(0, 8), Color.WHITE, 2.0
	)
	draw_arc(center, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.3), 3.0, true)
	var target := hammer.get_locked_target()
	var surface := hammer.get_locked_surface()
	var layer := hammer.get_locked_layer()
	if is_instance_valid(target):
		draw_arc(
			center,
			radius,
			start + target.band_min * TAU,
			start + target.band_max * TAU,
			24,
			Color(0.4, 1.0, 0.45),
			7.0,
			true,
		)
	elif is_instance_valid(surface) or is_instance_valid(layer):
		draw_arc(
			center,
			radius,
			start + G.settings.hammer_surface_damage_charge * TAU,
			start + TAU,
			24,
			Color(1.0, 0.35, 0.3),
			7.0,
			true,
		)
	elif hammer.is_locked_prop_green():
		# The wonky radio: any charge fixes it, so the green
		# band generously covers the whole ring.
		draw_arc(
			center,
			radius,
			start,
			start + TAU,
			48,
			Color(0.4, 1.0, 0.45),
			7.0,
			true,
		)
	var fill_color := Color(1.0, 0.85, 0.3)
	if (
		(is_instance_valid(target) and hammer.is_charge_in_band())
		or hammer.is_locked_prop_green()
	):
		fill_color = Color(0.4, 1.0, 0.45)
	draw_arc(
		center,
		radius,
		start,
		start + hammer.charge * TAU,
		48,
		fill_color,
		4.0,
		true,
	)
