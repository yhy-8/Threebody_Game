extends Node
## 项目入口 — 加载初始菜单


func _ready() -> void:
	get_tree().change_scene_to_file.call_deferred("res://scenes/main_menu/initial_menu.tscn")
