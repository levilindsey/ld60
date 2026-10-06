class_name StateMain
extends Node


enum State {
	TITLE,
	GAME,
	PAUSE,
	CREDITS,
}

var state := State.TITLE


func _enter_tree() -> void:
	G.state = self


## Runs with process_mode ALWAYS (set in state_main.tscn) so these
## transitions still fire while the tree is paused (TITLE / PAUSE /
## CREDITS all pause the tree).
func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.TITLE:
			if (
				event.is_action_pressed("jump")
				or event.is_action_pressed("ability")
			):
				transition(State.GAME)
		State.GAME:
			if event.is_action_pressed("pause"):
				transition(State.PAUSE)
		State.PAUSE:
			if event.is_action_pressed("pause"):
				transition(State.GAME)
		State.CREDITS:
			if (
				event.is_action_pressed("jump")
				or event.is_action_pressed("ability")
			):
				transition(State.GAME)
		_:
			pass


func start_game() -> void:
	var to_state := State.GAME if G.settings.start_in_game else State.TITLE
	transition(to_state)


## Branches are idempotent on purpose. There is no same-state early
## return, so the boot-time transition into the initial TITLE state
## still runs its side effects (pause + menu theme + HUD overlay).
func transition(to_state: State) -> void:
	state = to_state

	match to_state:
		State.TITLE:
			if not G.session.is_game_ended:
				G.game_panel.end_game()
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		State.GAME:
			if G.session.is_game_ended:
				G.game_panel.start_game()
			get_tree().paused = false
			G.audio.fade_to_main_theme()
		State.PAUSE:
			get_tree().paused = true
			G.audio.fade_to_menu_theme()
		State.CREDITS:
			if not G.session.is_game_ended:
				G.game_panel.end_game()
			get_tree().paused = true
			G.audio.fade_to_end_theme()
		_:
			G.error()

	G.hud.handle_state_transition(to_state)
