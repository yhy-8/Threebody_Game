class_name CapitalSelectionService
extends RefCounted
## Pure candidate ranking over already-public zone views; never receives hidden zones or future orbits.


func build_candidate_views(p_public_zone_views: Array, p_scenario_rules: Dictionary) -> Array:
	var result: Array = []
	for public_value in p_public_zone_views:
		if not public_value is Dictionary:
			continue
		var public_view: Dictionary = public_value
		var temperature := float(public_view.get("temperature", -273.15))
		var light := float(public_view.get("light_intensity", 0.0))
		if temperature < -65.0 or temperature > 75.0 or light < 0.015:
			continue
		var reasons: Array[String] = []
		var difficulties: Array[String] = []
		if temperature >= -10.0 and temperature <= 40.0:
			reasons.append("当前温度适合露天活动")
		else:
			difficulties.append("当前温度偏离舒适范围")
		if light >= 0.12 and light <= 0.85:
			reasons.append("当前光照可支持早期采集与栽培观察")
		elif light > 0.85:
			difficulties.append("当前光照强，需留意升温")
		else:
			difficulties.append("当前光照弱，食物获取可能困难")
		var terrain := str(public_view.get("terrain", "未知"))
		match terrain:
			"平原", "丘陵": reasons.append("可见地形较易步行和搭建居所")
			"盆地": reasons.append("低地可能汇集水源与植被迹象")
			"山地", "峡谷": difficulties.append("可见地形会增加出行和施工负担")
			"高原": difficulties.append("高地可能更冷且路径暴露")
		var score := _public_score(public_view)
		result.append({
			"zone_id": int(public_view.get("zone_id", -1)),
			"known": public_view.duplicate(true),
			"reasons": reasons,
			"known_difficulties": difficulties,
			"unknown_fields": ["地下矿藏", "精确储量", "长期气候规律", "未来恒星轨道"],
			"public_score": score,
			"confidence": clampf(0.35 + reasons.size() * 0.08 - difficulties.size() * 0.04, 0.2, 0.72),
			"rule_note": "规则保证稳定纪元 %.1f 年；这不是文明的轨道预测。" % float(p_scenario_rules.get("stable_years", 0.0)),
		})
	return result


func rank_candidates(p_candidate_views: Array) -> Array:
	var ranked := p_candidate_views.duplicate(true)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(float(a.get("public_score", 0.0)), float(b.get("public_score", 0.0))):
			return float(a.get("public_score", 0.0)) > float(b.get("public_score", 0.0))
		return int(a.get("zone_id", 0)) < int(b.get("zone_id", 0))
	)
	return ranked


func validate_selection(p_zone_id: int, p_public_view: Dictionary) -> Dictionary:
	if p_zone_id < 0 or int(p_public_view.get("zone_id", -1)) != p_zone_id:
		return {"success": false, "message": "起始区域不在公开候选中"}
	var temperature := float(p_public_view.get("temperature", -273.15))
	var light := float(p_public_view.get("light_intensity", 0.0))
	if temperature < -65.0 or temperature > 75.0 or light < 0.015:
		return {"success": false, "message": "当前公开环境不满足最低生存条件"}
	return {"success": true, "message": ""}


func _public_score(p_view: Dictionary) -> float:
	var temperature := float(p_view.get("temperature", -273.15))
	var light := float(p_view.get("light_intensity", 0.0))
	var temperature_score := 1.0 - clampf(absf(temperature - 20.0) / 95.0, 0.0, 1.0)
	var light_score := 1.0 - clampf(absf(light - 0.45) / 0.8, 0.0, 1.0)
	var terrain_score := {
		"平原": 1.0, "丘陵": 0.82, "盆地": 0.78, "高原": 0.62, "峡谷": 0.55, "山地": 0.48,
	}.get(str(p_view.get("terrain", "")), 0.4) as float
	return temperature_score * 0.48 + light_score * 0.32 + terrain_score * 0.20
