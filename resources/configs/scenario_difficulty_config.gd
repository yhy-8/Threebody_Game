@tool
class_name ScenarioDifficultyConfig
extends Resource
## 版本化场景难度目录；运行时难度数值的唯一来源。

@export var config_version: int = 0
@export var default_preset_id: StringName
@export var presets: Array[Resource] = []
@export var custom_enabled: bool = true
@export var custom_display_name: String = "自定义"
@export_multiline var custom_description: String = "手动指定进入真实三体混沌前的稳定年数。"
@export var custom_min_years: float = 0.0
@export var custom_max_years: float = 0.0
@export var days_per_year: float = 0.0


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if config_version <= 0:
		errors.append("config_version 必须大于 0")
	if not is_finite(days_per_year) or days_per_year <= 0.0:
		errors.append("days_per_year 必须是有限正数")
	if not is_finite(custom_min_years) or custom_min_years < 0.0:
		errors.append("custom_min_years 必须是有限非负数")
	if not is_finite(custom_max_years) or custom_max_years < custom_min_years:
		errors.append("custom_max_years 必须是有限数且不小于下限")

	var ids: Dictionary = {}
	for preset in presets:
		if preset == null:
			errors.append("presets 包含空资源")
			continue
		var preset_id := String(preset.id)
		if preset_id.is_empty():
			errors.append("难度预设 ID 不能为空")
		elif ids.has(preset_id):
			errors.append("难度预设 ID 重复：%s" % preset_id)
		else:
			ids[preset_id] = preset
		if preset.display_name.strip_edges().is_empty():
			errors.append("难度 %s 缺少显示名称" % preset_id)
		if not is_finite(preset.stable_years) or preset.stable_years < 0.0:
			errors.append("难度 %s 的 stable_years 必须是有限非负数" % preset_id)

	var default_preset: Resource = ids.get(String(default_preset_id))
	if default_preset == null or not default_preset.selectable:
		errors.append("default_preset_id 必须引用可选预设")
	return errors


func get_selectable_presets() -> Array[Resource]:
	var result: Array[Resource] = []
	for preset in presets:
		if preset != null and preset.selectable:
			result.append(preset)
	result.sort_custom(func(first: Resource, second: Resource): return first.sort_order < second.sort_order)
	return result


func get_preset(p_id: StringName) -> Resource:
	for preset in presets:
		if preset != null and preset.id == p_id:
			return preset
	return null


func create_snapshot(p_id: StringName, p_custom_years: float = NAN) -> Dictionary:
	var errors := validate()
	if not errors.is_empty():
		return {"success": false, "errors": errors}

	var stable_years_value: float
	var display_name_value: String
	var description_value: String
	if p_id == &"custom":
		if not custom_enabled:
			return {"success": false, "errors": PackedStringArray(["当前配置未启用自定义难度"])}
		if not is_finite(p_custom_years) or p_custom_years < custom_min_years or p_custom_years > custom_max_years:
			return {"success": false, "errors": PackedStringArray([
				"自定义稳定年数必须在 %.0f 至 %.0f 之间" % [custom_min_years, custom_max_years],
			])}
		stable_years_value = p_custom_years
		display_name_value = custom_display_name
		description_value = custom_description
	else:
		var preset: Resource = get_preset(p_id)
		if preset == null or not preset.selectable:
			return {"success": false, "errors": PackedStringArray(["未知或不可选的难度 ID：%s" % String(p_id)])}
		stable_years_value = preset.stable_years
		display_name_value = preset.display_name
		description_value = preset.description

	return {
		"success": true,
		"snapshot": {
			"difficulty_config_version": config_version,
			"difficulty_id": String(p_id),
			"difficulty_display_name": display_name_value,
			"difficulty_description": description_value,
			"stable_years": stable_years_value,
			"days_per_year": days_per_year,
			"chaos_start_day": stable_years_value * days_per_year,
		},
	}
