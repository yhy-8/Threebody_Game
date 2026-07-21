@tool
class_name DifficultyPreset
extends Resource
## 单个开局难度预设。ID 与实际稳定年数会固化进存档。

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var stable_years: float = 0.0
@export var sort_order: int = 0
@export var selectable: bool = true
