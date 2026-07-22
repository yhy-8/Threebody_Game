extends Node
## Surface-observation coordinates, shared source data, visuals, and persistence.

const EntityScript = preload("res://scripts/simulation/entity_manager.gd")

var _failures: int = 0


func _ready() -> void:
	GameState.reset()
	GameState.set_developer_mode(true)
	_expect(GameState.new_game("区域观测测试"), "测试宇宙创建失败")
	_expect(GameState.confirm_capital(int(GameState.settlement_system.candidate_views[0].get("zone_id", -1))).get("success", false), "测试首都确认失败")
	GameState.paused = true
	var packed: PackedScene = load("res://scenes/game/region_observation_view.tscn")
	var view = packed.instantiate()
	add_child(view)
	await get_tree().process_frame

	var snapshot := GameState.get_state()
	view.set_observed_zone(0)
	view.refresh_from_state(snapshot)
	var first: Dictionary = view.get_body_altitude_azimuth(0)
	view.set_observed_zone(1)
	view.refresh_from_state(snapshot)
	var second: Dictionary = view.get_body_altitude_azimuth(0)
	_expect(not first.is_empty() and not second.is_empty(), "区域天空未生成恒星地平坐标")
	_expect(
		absf(float(first.get("altitude", 0.0)) - float(second.get("altitude", 0.0))) > 0.0001
		or absf(float(first.get("azimuth", 0.0)) - float(second.get("azimuth", 0.0))) > 0.0001,
		"不同经纬度区域得到相同的恒星高度与方位",
	)

	var back_zone := _find_backlit_zone(snapshot, 0)
	_expect(back_zone >= 0, "未找到背光区域")
	if back_zone >= 0:
		view.set_observed_zone(back_zone)
		view.refresh_from_state(snapshot)
		var back_observation: Dictionary = view.get_body_altitude_azimuth(0)
		_expect(not back_observation.get("above_horizon", true), "背光区域恒星未落到地平线以下")
		var renderer = view.get_node("ViewportContainer/SubViewport/Sky3D/CelestialRenderer")
		var body_nodes: Array = renderer.get_body_nodes()
		_expect(not body_nodes.is_empty() and not body_nodes[0].visible, "地平线遮罩未隐藏地下恒星")

	var source_snapshot: Array = view.get_render_source_snapshot()
	var stars: Array = snapshot.get("environment", {}).get("stars", [])
	_expect(source_snapshot.size() == 3, "地表天空没有使用完整的三颗恒星快照")
	if not source_snapshot.is_empty() and not stars.is_empty():
		_expect(source_snapshot[0]["position"] == stars[0]["position"], "地表天空与星图的天体位置来源不一致")
		_expect(source_snapshot[0]["color"] == stars[0]["color"], "地表天空与星图的恒星颜色来源不一致")
		_expect(source_snapshot[0]["collision_state"] == snapshot.get("game_over", false), "地表天空碰撞状态未取自全局快照")

	var building = EntityScript.GameBuilding.new(9001, "测试观测站", "observatory", 0)
	GameState.entities.add_building(building)
	GameState.planet_zones.add_building_to_zone(0, building.id)
	view.set_observed_zone(0)
	view.refresh_from_state(GameState.get_state())
	_expect(9001 in view.get_building_visual_ids(), "地面建筑插槽未按区域实体增量创建视觉节点")

	_expect(GameState.set_observed_zone(17), "无法设置合法观察区域")
	var saved := GameState.to_dict()
	_expect(saved.get("observed_zone_id", -1) == 17, "观察区域未写入存档")
	_expect(GameState.from_dict(saved) and GameState.observed_zone_id == 17, "观察区域存档往返失败")
	var obsolete := saved.duplicate(true)
	obsolete["schema_version"] = GameState.SAVE_SCHEMA_VERSION - 1
	_expect(not GameState.from_dict(obsolete), "旧 schema 存档没有被拒绝")
	_expect(GameState.observed_zone_id == 17, "拒绝旧 schema 时覆盖了当前观察区域")
	var incomplete := saved.duplicate(true)
	incomplete.erase("regional_logistics")
	_expect(not GameState.from_dict(incomplete), "缺少当前区域字段的存档没有被拒绝")
	_expect(GameState.observed_zone_id == 17, "拒绝不完整存档时覆盖了当前状态")

	view.queue_free()
	GameState.reset()
	GameState.set_developer_mode(false)
	if _failures == 0:
		print("REGION_OBSERVATION_TEST_OK")
	get_tree().quit(_failures)


func _find_backlit_zone(p_snapshot: Dictionary, p_star_index: int) -> int:
	var stars: Array = p_snapshot.get("environment", {}).get("stars", [])
	if p_star_index < 0 or p_star_index >= stars.size():
		return -1
	var planet_position := Vector3.ZERO
	for star: Dictionary in stars:
		if star.get("is_planet", false):
			planet_position = _to_vector(star.get("position", {}))
			break
	var star_direction := (_to_vector(stars[p_star_index].get("position", {})) - planet_position).normalized()
	var best_zone := -1
	var best_dot := 1.0
	for zone_id in range(GameState.planet_zones.zones.size()):
		var dot_value: float = GameState.planet_zones.get_zone_normal(zone_id).dot(star_direction)
		if dot_value < best_dot:
			best_dot = dot_value
			best_zone = zone_id
	return best_zone if best_dot < 0.0 else -1


func _to_vector(p_value: Dictionary) -> Vector3:
	return Vector3(p_value.get("x", 0.0), p_value.get("y", 0.0), p_value.get("z", 0.0))


func _expect(p_condition: bool, p_message: String) -> void:
	if p_condition:
		return
	_failures += 1
	push_error(p_message)
