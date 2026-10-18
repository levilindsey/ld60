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
## The pointing hand shown by default everywhere. This texture
## replaces the arrow shape.
@export var point_cursor_texture: Texture2D
## Where the point cursor's hot spot sits, in the resized
## texture's pixels: the fingertip.
@export var point_cursor_hotspot := Vector2(18.0, 2.0)
## The open hand shown over things the empty hand can grab. Godot
## has no grab cursor shape, so this texture replaces the
## pointing-hand shape wherever the hand offers a grab.
@export var grab_cursor_texture: Texture2D
## Where the grab cursor's hot spot sits, in the resized
## texture's pixels: the palm.
@export var grab_cursor_hotspot := Vector2(27.0, 35.0)
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
## The gradient outline that marks what can be pressed next: a layer
## ready to go back on, a resting screw that can come back, a finished
## item and the outbox. Sprite2D art gets this material. ColorRect and
## Polygon2D art gets the same rim drawn by OutlineHint instead.
@export var outline_hint_material: ShaderMaterial
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
@export var phillips_repairable_scene: PackedScene
## The day's order: the items that arrive, one after another. The game is
## won after the last one goes into the outbox.
@export var item_queue: Array[Repairable.Type] = []
@export_group("")

@export_group("Tools")
@export var flat_head_screw_driver_scene: PackedScene
@export var rag_scene: PackedScene
@export var air_blower_scene: PackedScene
@export var hammer_scene: PackedScene
## The placeholder bottle art stands in until the real one lands.
@export var glue_scene: PackedScene
@export var phillips_screw_driver_scene: PackedScene
@export_group("")

@export_group("Phillips")
## Slowest circle speed that still turns the screw, in radians
## per second. About half a turn per second.
@export var phillips_speed_min_rad_per_sec := 3.0
## Fastest circle speed that still turns the screw. Circling
## faster cams the bit out.
@export var phillips_speed_max_rad_per_sec := 7.0
## The speed at the end of the gauge's sweep.
@export var phillips_gauge_max_rad_per_sec := 10.0
## Grip gained per second while the speed is in the band.
@export var phillips_fill_rate := 0.25
## Grip lost per second while the speed is out of the band.
@export var phillips_drain_rate := 0.375
## Grip a removal starts with, and an install starts with.
@export var phillips_meter_start := 0.3
@export var phillips_install_meter_start := 0.6
## Seconds input pauses after a cam-out.
@export var phillips_cam_out_pause_sec := 0.5
## Grace seconds at the start, while the gauge scales in.
@export var phillips_intro_sec := 0.33
@export_group("")

@export_group("Rag")
## Hit points of grime removed per second at the speed cap.
@export var rag_wipe_rate := 2.0
## Drag speed in pixels per second that wipes at the full rate.
@export var rag_speed_cap_px_per_sec := 400.0
## Extra grime hit points removed each time the drag reverses.
@export var rag_reversal_bonus := 0.12
## Pixels wiped on a sensitive surface before it is ruined.
@export var sensitive_ruin_distance_px := 300.0
## The share of that distance that already costs a minor smear.
@export var sensitive_minor_fraction := 0.3
@export_group("")

@export_group("Air blower")
## How far a puff reaches, in pixels.
@export var air_cone_length_px := 200.0
## Half of the puff cone's width, in degrees.
@export var air_cone_half_angle_deg := 15.0
## Dust hit points removed per second of full strength spray.
@export var air_blow_rate := 1.5
## One tap counts as this many seconds of spray.
@export var air_puff_sec := 0.4
## Seconds the bulb stays squeezed after a tap.
@export var air_squeeze_sec := 0.18
## Spin a fan gains per second of full strength spray.
@export var fan_spin_gain := 8.0
@export_group("")

@export_group("Hammer")
## Seconds of holding that fill the strength ring.
@export var hammer_charge_sec := 1.2
## Degrees the hammer lifts at full charge.
@export var hammer_max_windup_deg := 70.0
## Seconds the swing down takes.
@export var hammer_swing_sec := 0.08
## Seconds hammer and target freeze on impact.
@export var hammer_hit_stop_sec := 0.06
## Seconds the recoil takes after a swing.
@export var hammer_recoil_sec := 0.2
## Strength ring radius in pixels, and the bigger touch one.
@export var hammer_reticle_radius_px := 40.0
@export var hammer_reticle_radius_touch_px := 64.0
## Past the band by this much, a hit is far too hard.
@export var hammer_far_margin := 0.2
## Charge where a bare surface starts to take damage.
@export var hammer_surface_damage_charge := 0.55
@export_group("")

@export_group("Glue")
## Planned (LX22). Coverage gained per second on a crack sample.
@export var glue_flow_rate := 2.0
## Seconds a covered crack dries before it is done.
@export var glue_dry_sec := 3.0
## Coverage past this on one sample spawns a blob and a defect.
@export var glue_blob_coverage := 1.5
## How close the nozzle must be to a crack sample, in pixels.
@export var glue_radius_px := 10.0
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

@export_group("Screw rest")
## Where a pulled-out screw waits on the bench while its layer is off
## (docs/design/screw_pullout.md). The first removed screw rests at the
## first position, and each next one a step along the row. A full row
## starts a new one a row step away.
@export var screw_rest_first_position := Vector2(-440.0, 80.0)
@export var screw_rest_step := Vector2(36.0, 0.0)
@export var screw_rest_row_step := Vector2(0.0, 56.0)
@export var screw_rest_row_size := 5
## Seconds a screw takes to slide from its hole to its rest spot, and back.
@export var screw_travel_sec := 0.4
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
		Repairable.Type.TEST_PHILLIPS_REPAIRABLE:
			return phillips_repairable_scene
		_:
			G.fatal()
			return null


func get_tool_scene_from_type(type: Tool.Type) -> PackedScene:
	match type:
		Tool.Type.FLAT_HEAD_SCREW_DRIVER:
			return flat_head_screw_driver_scene
		Tool.Type.RAG:
			return rag_scene
		Tool.Type.AIR_BLOWER:
			return air_blower_scene
		Tool.Type.HAMMER:
			return hammer_scene
		Tool.Type.GLUE:
			return glue_scene
		Tool.Type.PHILLIPS_SCREW_DRIVER:
			return phillips_screw_driver_scene
		_:
			G.fatal()
			return null
