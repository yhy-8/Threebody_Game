class_name RegionMovementSystem
extends RefCounted
## Serializable travel operations. People and supplies remain unavailable until physical arrival.

signal operation_departed(operation_id: String, operation_type: String)
signal operation_arrived(operation_id: String, operation_type: String, zone_id: int)

const STATE_VERSION := 1
const WALK_DAYS_PER_SEGMENT := 2.0
const FOOD_PER_PERSON_PER_DAY := 0.04

enum OperationStatus { TRAVELLING, RETURNING, STRANDED, ARRIVED, CANCELLED, PAUSED }

var operations: Dictionary = {}
var _next_operation_number: int = 1


func plan_route(p_origin_zone_id: int, p_destination_zone_id: int, p_planet_zones, p_settlement_system = null, p_allow_unknown_destination: bool = false) -> Dictionary:
	var route := _breadth_first_route(p_origin_zone_id, p_destination_zone_id, p_planet_zones, p_settlement_system, p_allow_unknown_destination)
	if route.is_empty():
		return {"success": false, "message": "目前没有可确认的陆路路线"}
	var segment_count := maxi(0, route.size() - 1)
	return {
		"success": true,
		"route": route,
		"segment_count": segment_count,
		"travel_days": float(segment_count) * WALK_DAYS_PER_SEGMENT,
		"cost_explanation": "步行路线 %d 段 × %.1f 天；口粮按每人每天 %.2f 计" % [segment_count, WALK_DAYS_PER_SEGMENT, FOOD_PER_PERSON_PER_DAY],
	}


func start_operation(p_type: String, p_origin_zone_id: int, p_destination_zone_id: int,
		p_population_count: int, p_cargo: Dictionary, p_planet_zones, p_settlement_system,
		p_logistics, p_entities, p_return_to_origin: bool = false) -> Dictionary:
	if p_type not in ["migration", "transport", "exploration", "capital_relocation"]:
		return {"success": false, "message": "未知区域行动类型"}
	if p_population_count <= 0:
		return {"success": false, "message": "行动至少需要 1 名成员"}
	var locally_available: int = int(p_settlement_system.get_population(p_origin_zone_id))
	if p_population_count > locally_available or p_population_count > p_entities.get_idle_population():
		return {"success": false, "message": "出发区域闲置人口不足（需要 %d，当地可用 %d）" % [p_population_count, maxi(0, locally_available)]}
	var route_plan: Dictionary = plan_route(p_origin_zone_id, p_destination_zone_id, p_planet_zones, p_settlement_system, p_type == "exploration")
	if not route_plan.get("success", false):
		return route_plan
	var travel_days: float = float(route_plan["travel_days"])
	var total_route_days: float = travel_days * (2.0 if p_return_to_origin else 1.0)
	var required_food: float = p_population_count * total_route_days * FOOD_PER_PERSON_PER_DAY
	var manifest: Dictionary = p_cargo.duplicate()
	manifest["food"] = float(manifest.get("food", 0.0)) + required_food
	var operation_id: String = "region-op:%06d" % _next_operation_number
	var reserve_result: Dictionary = p_logistics.reserve_for_operation(operation_id, p_origin_zone_id, manifest)
	if not reserve_result.get("success", false):
		return reserve_result
	if not p_settlement_system.embark_population(p_origin_zone_id, p_population_count):
		p_logistics.release_operation_reserve(operation_id, p_origin_zone_id)
		return {"success": false, "message": "出发地人口状态已变化"}
	_next_operation_number += 1
	var route: Array = route_plan["route"]
	operations[operation_id] = {
		"operation_id": operation_id,
		"type": p_type,
		"origin_zone_id": p_origin_zone_id,
		"destination_zone_id": p_destination_zone_id,
		"population_count": p_population_count,
		"cargo": p_cargo.duplicate(),
		"route": route.duplicate(),
		"route_index": 0,
		"segment_progress_days": 0.0,
		"elapsed_days": 0.0,
		"outbound_travel_days": travel_days,
		"return_to_origin": p_return_to_origin,
		"status": OperationStatus.TRAVELLING,
		"current_zone_id": p_origin_zone_id,
		"food_required": required_food,
		"food_consumed": 0.0,
		"cost_explanation": route_plan["cost_explanation"],
	}
	operation_departed.emit(operation_id, p_type)
	return {"success": true, "message": "行动已出发：%s" % route_plan["cost_explanation"], "operation_id": operation_id, "operation": operations[operation_id].duplicate(true)}


func update(p_dt_days: float, p_settlement_system, p_logistics, p_entities, p_exploration, p_planet_zones, p_game_day: float) -> void:
	if p_dt_days <= 0.0:
		return
	for operation_id in operations.keys():
		var operation: Dictionary = operations[operation_id]
		if int(operation.get("status", OperationStatus.ARRIVED)) not in [OperationStatus.TRAVELLING, OperationStatus.RETURNING]:
			continue
		var population_count: int = int(operation.get("population_count", 0))
		var food_needed: float = population_count * FOOD_PER_PERSON_PER_DAY * p_dt_days
		var consumed: float = float(p_logistics.consume_operation_resource(str(operation_id), "food", food_needed, p_entities))
		operation["food_consumed"] = float(operation.get("food_consumed", 0.0)) + consumed
		if consumed + 1e-6 < food_needed:
			operation["status"] = OperationStatus.STRANDED
			continue
		operation["elapsed_days"] = float(operation.get("elapsed_days", 0.0)) + p_dt_days
		operation["segment_progress_days"] = float(operation.get("segment_progress_days", 0.0)) + p_dt_days
		while float(operation["segment_progress_days"]) + 1e-9 >= WALK_DAYS_PER_SEGMENT:
			operation["segment_progress_days"] = float(operation["segment_progress_days"]) - WALK_DAYS_PER_SEGMENT
			if not _advance_one_segment(operation, p_settlement_system, p_logistics, p_entities, p_exploration, p_planet_zones, p_game_day):
				break


func cancel_operation(p_operation_id: String, p_settlement_system, p_logistics) -> Dictionary:
	if not operations.has(p_operation_id):
		return {"success": false, "message": "区域行动不存在"}
	var operation: Dictionary = operations[p_operation_id]
	if int(operation.get("status", OperationStatus.ARRIVED)) in [OperationStatus.ARRIVED, OperationStatus.CANCELLED]:
		return {"success": false, "message": "行动已经结束"}
	var current_zone_id := int(operation.get("current_zone_id", operation.get("origin_zone_id", -1)))
	p_settlement_system.disembark_population(current_zone_id, int(operation.get("population_count", 0)))
	p_logistics.release_operation_reserve(p_operation_id, current_zone_id)
	operation["status"] = OperationStatus.CANCELLED
	return {"success": true, "message": "行动已在区域 #%d 终止；剩余人员与物资留在当地" % current_zone_id}


func pause_operation(p_operation_id: String) -> Dictionary:
	if not operations.has(p_operation_id):
		return {"success": false, "message": "区域行动不存在"}
	var operation: Dictionary = operations[p_operation_id]
	var status := int(operation.get("status", OperationStatus.ARRIVED))
	if status not in [OperationStatus.TRAVELLING, OperationStatus.RETURNING]:
		return {"success": false, "message": "只有行进中的队伍可暂停"}
	operation["status_before_pause"] = status
	operation["status"] = OperationStatus.PAUSED
	return {"success": true, "message": "行动已暂停；期间不消耗行程口粮"}


func resume_operation(p_operation_id: String) -> Dictionary:
	if not operations.has(p_operation_id):
		return {"success": false, "message": "区域行动不存在"}
	var operation: Dictionary = operations[p_operation_id]
	if int(operation.get("status", OperationStatus.ARRIVED)) != OperationStatus.PAUSED:
		return {"success": false, "message": "行动当前未暂停"}
	var resumed_status := int(operation.get("status_before_pause", OperationStatus.TRAVELLING))
	if resumed_status not in [OperationStatus.TRAVELLING, OperationStatus.RETURNING]:
		resumed_status = OperationStatus.TRAVELLING
	operation["status"] = resumed_status
	operation.erase("status_before_pause")
	return {"success": true, "message": "行动已继续"}


func get_reserved_population() -> int:
	var total := 0
	for operation in operations.values():
		if int(operation.get("status", OperationStatus.ARRIVED)) in [OperationStatus.TRAVELLING, OperationStatus.RETURNING, OperationStatus.STRANDED, OperationStatus.PAUSED]:
			total += maxi(0, int(operation.get("population_count", 0)))
	return total


func get_reserved_population_at_zone(p_zone_id: int) -> int:
	var total := 0
	for operation in operations.values():
		if int(operation.get("origin_zone_id", -1)) == p_zone_id and int(operation.get("status", OperationStatus.ARRIVED)) in [OperationStatus.TRAVELLING, OperationStatus.RETURNING, OperationStatus.STRANDED, OperationStatus.PAUSED]:
			total += maxi(0, int(operation.get("population_count", 0)))
	return total


func get_state() -> Dictionary:
	return {"state_version": STATE_VERSION, "next_operation_number": _next_operation_number, "operations": operations.duplicate(true)}


func load_state(p_data: Dictionary) -> bool:
	if not p_data.get("operations", {}) is Dictionary:
		return false
	_next_operation_number = maxi(1, int(p_data.get("next_operation_number", 1)))
	operations = (p_data.get("operations", {}) as Dictionary).duplicate(true)
	return true


func _advance_one_segment(p_operation: Dictionary, p_settlement_system, p_logistics, p_entities, p_exploration, p_planet_zones, p_game_day: float) -> bool:
	var route: Array = p_operation.get("route", [])
	var route_index: int = int(p_operation.get("route_index", 0))
	var returning: bool = int(p_operation.get("status", OperationStatus.TRAVELLING)) == OperationStatus.RETURNING
	var next_index: int = route_index - 1 if returning else route_index + 1
	if next_index >= 0 and next_index < route.size():
		p_operation["route_index"] = next_index
		p_operation["current_zone_id"] = int(route[next_index])
		if (not returning and next_index < route.size() - 1) or (returning and next_index > 0):
			return true
	if not returning and bool(p_operation.get("return_to_origin", false)):
		if str(p_operation.get("type", "")) == "exploration":
			p_exploration.complete_survey(p_operation, p_planet_zones, p_settlement_system, p_game_day)
		elif str(p_operation.get("type", "")) == "transport":
			p_logistics.deliver_operation_resources(
				str(p_operation.get("operation_id", "")),
				int(p_operation.get("destination_zone_id", -1)),
				p_operation.get("cargo", {})
			)
		p_operation["status"] = OperationStatus.RETURNING
		p_operation["route_index"] = route.size() - 1
		return true
	var arrival_zone: int = int(p_operation.get("origin_zone_id", -1)) if returning else int(p_operation.get("destination_zone_id", -1))
	p_settlement_system.disembark_population(arrival_zone, int(p_operation.get("population_count", 0)))
	p_logistics.release_operation_reserve(str(p_operation.get("operation_id", "")), arrival_zone)
	p_operation["current_zone_id"] = arrival_zone
	p_operation["status"] = OperationStatus.ARRIVED
	if str(p_operation.get("type", "")) == "capital_relocation":
		if p_settlement_system.complete_capital_relocation(arrival_zone, p_game_day):
			p_entities.global_efficiency = minf(p_entities.global_efficiency, 0.85)
	operation_arrived.emit(str(p_operation.get("operation_id", "")), str(p_operation.get("type", "")), arrival_zone)
	return false


func _breadth_first_route(p_origin_zone_id: int, p_destination_zone_id: int, p_planet_zones, p_settlement_system, p_allow_unknown_destination: bool) -> Array:
	if p_planet_zones.get_zone(p_origin_zone_id) == null or p_planet_zones.get_zone(p_destination_zone_id) == null:
		return []
	if p_origin_zone_id == p_destination_zone_id:
		return [p_origin_zone_id]
	var frontier: Array[int] = [p_origin_zone_id]
	var came_from: Dictionary = {p_origin_zone_id: -1}
	while not frontier.is_empty():
		var current: int = int(frontier.pop_front())
		for neighbor_value in p_planet_zones.get_zone_neighbors(current):
			var neighbor := int(neighbor_value)
			if came_from.has(neighbor):
				continue
			if p_settlement_system != null:
				var level := int(p_settlement_system.get_zone_knowledge(neighbor).get("level", 0))
				var allowed_destination := neighbor == p_destination_zone_id and p_allow_unknown_destination
				if level < p_settlement_system.ZoneKnowledgeLevel.FAMILIAR and not allowed_destination:
					continue
			came_from[neighbor] = current
			if neighbor == p_destination_zone_id:
				var route: Array[int] = [neighbor]
				var cursor: int = current
				while cursor >= 0:
					route.push_front(cursor)
					cursor = int(came_from.get(cursor, -1))
				return route
			frontier.append(neighbor)
	return []
