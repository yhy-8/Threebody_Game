extends Control
## 游戏内暂停菜单


func _ready() -> void:
	%ResumeButton.pressed.connect(_on_resume_pressed)
	%SaveButton.pressed.connect(_on_save_pressed)
	%LoadButton.pressed.connect(_on_load_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%MainMenuButton.pressed.connect(_on_main_menu_pressed)


func _on_resume_pressed() -> void:
	EventBus.game_paused.emit(false)
	get_tree().change_scene_to_file("res://scenes/game/main_screen.tscn")


func _on_save_pressed() -> void:
	SaveManager.save_game(null, "autosave", "default")


func _on_load_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/start_game_menu.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/settings_screen.tscn")


func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/initial_menu.tscn")
