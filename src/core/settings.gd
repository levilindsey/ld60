class_name Settings
extends Resource


enum PhysicsLayer {
	NONE = 0,
	TOOLS = 1 << 0,
	REPAIRABLES = 1 << 1,
	INTERACTION_POINTS = 1 << 2,
	TABLE = 1 << 3,
	TOOL_HOLDERS = 1 << 4,
	SURFACES = 1 << 5,
	PARTS = 1 << 6,
}

# --- General configuration ---

@export var dev_mode := true
@export var show_debug_console := false

@export var start_in_game := true
@export var full_screen := false
@export var move_preview_windows_to_other_display := true
@export var mute_music := false
@export var pauses_on_focus_out := true
@export var is_screenshot_hotkey_enabled := true

@export var show_hud := true

# --- Game configuration ---

@export var default_gravity_acceleration := 1400.0

@export var default_level_scene: PackedScene

@export_group("Hand")
## Seconds for a held tool to ease into the pointer instead of jumping.
@export var tool_follow_ease_sec := 0.2
## Seconds a tool shakes when a point doesn't accept it.
@export var nope_shake_sec := 0.2
@export var nope_shake_px := 5.0
## Seconds the "nope" icon stays up.
@export var nope_icon_sec := 0.6
@export_group("")

@export_group("Layers")
## Seconds a loose layer waits before it lifts off.
@export var layer_lift_delay_sec := 0.3
## Seconds a layer takes to move to or from the set-aside spot.
@export var layer_move_sec := 0.4
## Scale of a set-aside layer, relative to its scale on the item.
@export var set_aside_scale := 0.8
## Offset between set-aside layers stacked on the spot.
@export var set_aside_stack_offset := Vector2(10.0, -10.0)
## Seconds and pixels of the shake when an unfinished item is pressed.
@export var item_shake_sec := 0.3
@export var item_shake_px := 4.0
## Seconds of one pulse on a point that still needs work.
@export var point_pulse_sec := 0.4
@export_group("")

@export_group("Item flow")
## Seconds an item takes to drop in from above and land.
@export var item_arrival_sec := 0.6
## The most an arriving item is turned, in degrees. It straightens as it
## lands.
@export var item_arrival_angle_max_deg := 8.0
## The camera shake when an item lands.
@export var item_landing_shake_px := 7.0
@export var item_landing_shake_sec := 0.15
## Seconds an item takes to ease back when it is dropped away from the
## outbox.
@export var item_return_sec := 0.3
## Seconds an item takes to drop into the tray, and then to slide off the
## left edge of the screen.
@export var item_tray_drop_sec := 0.15
@export var item_leave_sec := 0.4
## Seconds after an item goes into the outbox before the next one arrives.
@export var next_item_delay_sec := 0.5
## The most a dragged item tilts, in degrees, and the sideways drag speed
## in pixels per second that tilts it that far.
@export var drag_tilt_max_deg := 8.0
@export var drag_tilt_full_speed := 900.0
## How fast a dragged item's tilt catches up with its target. Higher is
## quicker.
@export var drag_tilt_follow_rate := 12.0
## The outline that glows around a finished item's top layer. Only
## Sprite2D art shows it. Placeholder art gets the glow pulse alone.
@export var finished_outline_material: ShaderMaterial
## The burst of sparkles when an item is finished.
@export var finish_sparkle_scene: PackedScene
@export_group("")


@export_group("Logs")
## Logs with these categories won't be shown.
@export var excluded_log_categories: Array[StringName] = [
	#ScaffolderLog.CATEGORY_DEFAULT,
	#ScaffolderLog.CATEGORY_CORE_SYSTEMS,
	ScaffolderLog.CATEGORY_SYSTEM_INITIALIZATION,
	#ScaffolderLog.CATEGORY_PLAYER_ACTIONS,
	#ScaffolderLog.CATEGORY_INTERACTION,
	#ScaffolderLog.CATEGORY_BEHAVIORS,
	#ScaffolderLog.CATEGORY_GAME_STATE,
]
## If true, warning logs will be shown regardless of category filtering.
@export var force_include_log_warnings := true
@export var include_category_in_logs := true
@export var verbosity := ScaffolderLog.Verbosity.NORMAL
@export_group("")

@export_group("Repairables")
@export var flat_head_screw_repairable_scene: PackedScene
## The day's order: the items that arrive, one after another. The game is
## won after the last one goes into the outbox.
@export var item_queue: Array[Repairable.Type] = []
@export_group("")

@export_group("Tools")
@export var flat_head_screw_driver_scene: PackedScene
@export_group("")

@export_group("Quality")
## The points each kind of defect costs. See RepairQuality.Defect.
@export var screw_damage_points := 2
@export var screw_stripped_points := 10
@export var pliers_scratch_points := 3
@export var small_dent_points := 8
@export var large_dent_points := 12
@export var crack_points := 15
@export var yanked_part_points := 8
@export var minor_smear_points := 3
@export var ruined_smear_points := 10
@export var oil_drip_points := 4
@export var glue_blob_points := 5
## A repair loses some points for every full interval it runs past its par
## time, up to a maximum.
@export var time_penalty_interval_sec := 2.0
@export var time_penalty_points_per_interval := 1
@export var time_penalty_max_points := 30
## The score that earns each number of stars. A lower score earns one star.
@export var three_star_score := 85
@export var two_star_score := 60
## The floating number that shows a defect's cost.
@export var defect_popup_scene: PackedScene
@export_group("")

@export_group("Flathead")
## Seconds one twist takes to turn the screw (docs/design/flathead.md).
@export var flathead_twist_duration_sec := 1.0
## Degrees one twist turns the screw and the driver while it comes out.
@export var flathead_twist_angle_deg := 90.0
## Seconds between twists, with no drift. The window to recenter.
@export var flathead_pause_sec := 0.35
## Seconds before a twist that the creak and the handle squash warn of it.
@export var flathead_telegraph_sec := 0.15
## Each twist drifts the tip by a random fraction of the screw's seat
## tolerance in this range. Keep the most under 1, so one twist can never
## unseat the tip.
@export var flathead_slip_min := 0.2
@export var flathead_slip_max := 0.6
@export_group("")

@export_group("Screw slide")
## How far a screw slides up the screen, in world pixels, while it turns
## all the way out. It slides back down as it turns in
## (docs/design/screws.md "Removal").
@export var screw_slide_px := 6.0
@export_group("")


## How many points a defect costs.
func get_defect_points(defect: RepairQuality.Defect) -> int:
	var points := 0
	match defect:
		RepairQuality.Defect.SCREW_DAMAGE:
			points = screw_damage_points
		RepairQuality.Defect.SCREW_STRIPPED:
			points = screw_stripped_points
		RepairQuality.Defect.PLIERS_SCRATCH:
			points = pliers_scratch_points
		RepairQuality.Defect.DENT_SMALL:
			points = small_dent_points
		RepairQuality.Defect.DENT_LARGE:
			points = large_dent_points
		RepairQuality.Defect.CRACK:
			points = crack_points
		RepairQuality.Defect.YANKED_PART:
			points = yanked_part_points
		RepairQuality.Defect.SMEAR_MINOR:
			points = minor_smear_points
		RepairQuality.Defect.SMEAR_RUINED:
			points = ruined_smear_points
		RepairQuality.Defect.OIL_DRIP:
			points = oil_drip_points
		RepairQuality.Defect.GLUE_BLOB:
			points = glue_blob_points
		_:
			G.fatal()
	return points


func get_repairable_scene_from_type(type: Repairable.Type) -> PackedScene:
	match type:
		Repairable.Type.TEST_FLAT_HEAD_SCREW_REPAIRABLE:
			return flat_head_screw_repairable_scene
		_:
			G.fatal()
			return null


func get_tool_scene_from_type(type: Tool.Type) -> PackedScene:
	match type:
		Tool.Type.FLAT_HEAD_SCREW_DRIVER:
			return flat_head_screw_driver_scene
		_:
			G.fatal()
			return null
