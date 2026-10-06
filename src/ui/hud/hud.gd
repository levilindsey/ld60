class_name Hud
extends PanelContainer


const _OVERLAY_FADE_SEC := 0.3


func _enter_tree() -> void:
	G.hud = self


func _ready() -> void:
	%TitleOverlay.modulate.a = 0.0
	%PauseOverlay.modulate.a = 0.0
	%CreditsOverlay.modulate.a = 0.0

	# Wait for G.settings to be assigned.
	await get_tree().process_frame

	visible = G.settings.show_hud
	# Sync with whatever state StateMain is already in (transitions
	# that fired before this HUD was ready are otherwise missed).
	handle_state_transition(G.state.state)


func handle_state_transition(to_state: StateMain.State) -> void:
	match to_state:
		StateMain.State.TITLE:
			fade_in(%TitleOverlay)
			fade_out(%PauseOverlay)
			fade_out(%CreditsOverlay)
		StateMain.State.GAME:
			fade_out(%TitleOverlay)
			fade_out(%PauseOverlay)
			fade_out(%CreditsOverlay)
		StateMain.State.PAUSE:
			fade_in(%PauseOverlay)
		StateMain.State.CREDITS:
			fade_out(%TitleOverlay)
			fade_out(%PauseOverlay)
			fade_in(%CreditsOverlay)
		_:
			G.error()


func fade_in(node: CanvasItem) -> void:
	var tween := node.create_tween()
	# The tree is paused on every non-GAME state, so overlay fades
	# must tick independently of SceneTree pause.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		node,
		"modulate:a",
		1.0,
		_OVERLAY_FADE_SEC)


func fade_out(node: CanvasItem) -> void:
	var tween := node.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(
		node,
		"modulate:a",
		0.0,
		_OVERLAY_FADE_SEC)
