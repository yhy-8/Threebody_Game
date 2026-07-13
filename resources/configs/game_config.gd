extends Resource
class_name GameConfig

@export var game_title: String = "三体文明"
@export var resolution: Vector2 = Vector2(1280, 720)
@export var fps: int = 60
@export var fullscreen: bool = false
@export var resizable: bool = true

## 时间倍率范围
@export var time_scale_default: float = 1.0
@export var time_scale_min: float = 0.1
@export var time_scale_max: float = 10.0
