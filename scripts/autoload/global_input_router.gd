extends Node
## 游戏内全局输入路由：统一处理暂停与返回，局部弹窗仍由所在场景关闭。

const PAUSE_SCREENS: Array[String] = [
	"main_screen", "zone_view", "knowledge_tree", "knowledge_policy", "decision", "starmap",
]

const BACK_TARGETS: Dictionary = {
	"main_screen": "res://scenes/game/game_menu.tscn",
	"game_menu": "res://scenes/game/main_screen.tscn",
	"zone_view": "res://scenes/game/main_screen.tscn",
	"knowledge_tree": "res://scenes/game/main_screen.tscn",
	"knowledge_policy": "res://scenes/tech_tree/tech_tree.tscn",
	"decision": "res://scenes/game/main_screen.tscn",
	"starmap": "res://scenes/game/main_screen.tscn",
}

const LOCAL_MODAL_NAMES: Array[String] = [
	"DeveloperOverlay", "GuidanceControlOverlay", "BuildOverlay", "HelpPanel", "SaveOverlay", "SaveBrowser",
]


func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if _is_space(key_event) and can_toggle_pause(GameState.current_screen):
		GameState.toggle_pause()
		get_viewport().set_input_as_handled()
		return

	if not _is_cancel(key_event) or _has_visible_local_modal():
		return
	var target := resolve_back_target(GameState.current_screen)
	if target.is_empty():
		return

	if GameState.current_screen == "main_screen" and not GameState.paused:
		GameState.toggle_pause()
	elif GameState.current_screen == "game_menu" and GameState.paused:
		GameState.toggle_pause()
	get_viewport().set_input_as_handled()
	get_tree().change_scene_to_file(target)


func can_toggle_pause(p_screen_name: String) -> bool:
	return GameState.game_started and p_screen_name in PAUSE_SCREENS


func resolve_back_target(p_screen_name: String) -> String:
	if p_screen_name == "settings":
		return GameState.settings_return_scene
	return str(BACK_TARGETS.get(p_screen_name, ""))


func _has_visible_local_modal() -> bool:
	for modal_name in LOCAL_MODAL_NAMES:
		var modal := get_tree().root.find_child(modal_name, true, false)
		if modal is CanvasItem and (modal as CanvasItem).is_visible_in_tree():
			return true
	return false


func _is_space(p_event: InputEventKey) -> bool:
	return p_event.keycode == KEY_SPACE or p_event.physical_keycode == KEY_SPACE


func _is_cancel(p_event: InputEventKey) -> bool:
	return p_event.is_action_pressed("ui_cancel") or p_event.keycode == KEY_ESCAPE or p_event.physical_keycode == KEY_ESCAPE
