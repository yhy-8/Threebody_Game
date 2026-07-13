extends Control
## 初始菜单 — 标题画面

@onready var start_button: Button = $MainVBox/StartGameBtn
@onready var settings_button: Button = $MainVBox/SettingsBtn
@onready var quit_button: Button = $MainVBox/QuitBtn


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)


func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/start_game_menu.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu/settings_screen.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
