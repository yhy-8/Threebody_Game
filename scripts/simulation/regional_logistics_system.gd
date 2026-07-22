class_name RegionalLogisticsSystem
extends RefCounted
## Keeps the physical location of the resources represented by EntityManager's civilization-wide totals.

const STATE_VERSION := 1
const NETWORK_TYPES: Array[String] = ["road", "pipeline", "grid"]

var local_inventories: Dictionary = {}
var operation_reserves: Dictionary = {}
var network_connections: Dictionary = {"road": [], "pipeline": [], "grid": []}


func initialize_at_capital(p_capital_zone_id: int, p_entities) -> void:
	local_inventories.clear()
	operation_reserves.clear()
	_initialize_networks()
	local_inventories[p_capital_zone_id] = _resource_snapshot(p_entities)


func get_local_inventory(p_zone_id: int) -> Dictionary:
	return (local_inventories.get(p_zone_id, {}) as Dictionary).duplicate()


func get_local_amount(p_zone_id: int, p_resource_id: String) -> float:
	return maxf(0.0, float((local_inventories.get(p_zone_id, {}) as Dictionary).get(p_resource_id, 0.0)))


func can_pay_local_cost(p_zone_id: int, p_cost: Dictionary) -> Dictionary:
	for resource_id in p_cost:
		var required: float = maxf(0.0, float(p_cost[resource_id]))
		var available: float = get_local_amount(p_zone_id, str(resource_id))
		if available + 1e-6 < required:
			return {
				"success": false,
				"message": "区域 #%d 的%s不足（需要 %.1f，当地 %.1f）" % [p_zone_id, str(resource_id), required, available],
			}
	return {"success": true, "message": ""}


func commit_local_cost(p_zone_id: int, p_cost: Dictionary) -> bool:
	if not can_pay_local_cost(p_zone_id, p_cost).get("success", false):
		return false
	var inventory: Dictionary = _ensure_inventory(p_zone_id)
	for resource_id in p_cost:
		inventory[resource_id] = maxf(0.0, float(inventory.get(resource_id, 0.0)) - maxf(0.0, float(p_cost[resource_id])))
	return true


func reserve_for_operation(p_operation_id: String, p_zone_id: int, p_manifest: Dictionary) -> Dictionary:
	if p_operation_id.is_empty() or operation_reserves.has(p_operation_id):
		return {"success": false, "message": "行动编号无效或已存在"}
	var availability: Dictionary = can_pay_local_cost(p_zone_id, p_manifest)
	if not availability.get("success", false):
		return availability
	if not commit_local_cost(p_zone_id, p_manifest):
		return {"success": false, "message": "地方库存状态已变化"}
	operation_reserves[p_operation_id] = {
		"origin_zone_id": p_zone_id,
		"resources": p_manifest.duplicate(),
	}
	return {"success": true, "message": "补给与载荷已进入在途库存"}


func consume_operation_resource(p_operation_id: String, p_resource_id: String, p_amount: float, p_entities) -> float:
	if p_amount <= 0.0 or not operation_reserves.has(p_operation_id):
		return 0.0
	var reserve: Dictionary = operation_reserves[p_operation_id]
	var resources: Dictionary = reserve.get("resources", {})
	var consumed: float = minf(maxf(0.0, float(resources.get(p_resource_id, 0.0))), p_amount)
	if consumed <= 0.0 or not p_entities.consume_resource(p_resource_id, consumed):
		return 0.0
	resources[p_resource_id] = maxf(0.0, float(resources.get(p_resource_id, 0.0)) - consumed)
	return consumed


func release_operation_reserve(p_operation_id: String, p_zone_id: int) -> Dictionary:
	if not operation_reserves.has(p_operation_id):
		return {}
	var reserve: Dictionary = operation_reserves[p_operation_id]
	var resources: Dictionary = (reserve.get("resources", {}) as Dictionary).duplicate()
	var inventory: Dictionary = _ensure_inventory(p_zone_id)
	for resource_id in resources:
		inventory[resource_id] = float(inventory.get(resource_id, 0.0)) + maxf(0.0, float(resources[resource_id]))
	operation_reserves.erase(p_operation_id)
	return resources


func deliver_operation_resources(p_operation_id: String, p_zone_id: int, p_manifest: Dictionary) -> Dictionary:
	if not operation_reserves.has(p_operation_id):
		return {"success": false, "message": "在途库存不存在"}
	var reserve: Dictionary = operation_reserves[p_operation_id]
	var resources: Dictionary = reserve.get("resources", {})
	for resource_id in p_manifest:
		if float(resources.get(resource_id, 0.0)) + 1e-6 < maxf(0.0, float(p_manifest[resource_id])):
			return {"success": false, "message": "在途载荷不足，无法卸货"}
	var destination: Dictionary = _ensure_inventory(p_zone_id)
	for resource_id in p_manifest:
		var amount := maxf(0.0, float(p_manifest[resource_id]))
		resources[resource_id] = maxf(0.0, float(resources.get(resource_id, 0.0)) - amount)
		destination[resource_id] = float(destination.get(resource_id, 0.0)) + amount
	return {"success": true, "message": "载荷已进入区域 #%d 地方库存" % p_zone_id}


func reconcile_after_simulation(p_before_totals: Dictionary, p_entities, p_buildings: Array) -> void:
	var after_totals: Dictionary = _resource_snapshot(p_entities)
	for resource_id in after_totals:
		var delta: float = float(after_totals[resource_id]) - float(p_before_totals.get(resource_id, 0.0))
		if delta > 1e-7:
			_distribute_production(str(resource_id), delta, p_buildings)
		elif delta < -1e-7:
			_remove_from_local_inventories(str(resource_id), -delta)
	_match_civilization_totals(after_totals)


func add_connection(p_network_type: String, p_zone_a: int, p_zone_b: int) -> bool:
	if p_network_type not in NETWORK_TYPES or p_zone_a < 0 or p_zone_b < 0 or p_zone_a == p_zone_b:
		return false
	var edge: Array = [mini(p_zone_a, p_zone_b), maxi(p_zone_a, p_zone_b)]
	if edge in network_connections[p_network_type]:
		return false
	network_connections[p_network_type].append(edge)
	return true


func has_connection(p_network_type: String, p_zone_a: int, p_zone_b: int) -> bool:
	if p_network_type not in NETWORK_TYPES:
		return false
	return [mini(p_zone_a, p_zone_b), maxi(p_zone_a, p_zone_b)] in network_connections[p_network_type]


func get_state() -> Dictionary:
	return {
		"state_version": STATE_VERSION,
		"local_inventories": local_inventories.duplicate(true),
		"operation_reserves": operation_reserves.duplicate(true),
		"network_connections": network_connections.duplicate(true),
	}


func load_state(p_data: Dictionary) -> bool:
	for section in ["local_inventories", "operation_reserves", "network_connections"]:
		if not p_data.get(section, {}) is Dictionary:
			return false
	local_inventories.clear()
	for zone_key in p_data.get("local_inventories", {}):
		local_inventories[int(zone_key)] = (p_data["local_inventories"][zone_key] as Dictionary).duplicate()
	operation_reserves = (p_data.get("operation_reserves", {}) as Dictionary).duplicate(true)
	_initialize_networks()
	var saved_networks: Dictionary = p_data.get("network_connections", {})
	for network_type in NETWORK_TYPES:
		network_connections[network_type] = (saved_networks.get(network_type, []) as Array).duplicate(true)
	return true


func _resource_snapshot(p_entities) -> Dictionary:
	var result: Dictionary = {}
	for resource_id in p_entities.resources:
		result[resource_id] = maxf(0.0, p_entities.get_resource(str(resource_id)))
	return result


func _ensure_inventory(p_zone_id: int) -> Dictionary:
	if not local_inventories.has(p_zone_id):
		local_inventories[p_zone_id] = {}
	return local_inventories[p_zone_id]


func _distribute_production(p_resource_id: String, p_amount: float, p_buildings: Array) -> void:
	var producers: Array = []
	var total_rate: float = 0.0
	for building in p_buildings:
		var rate: float = maxf(0.0, float(building.last_output_rate.get(p_resource_id, 0.0)))
		if rate > 0.0 and building.zone_id >= 0:
			producers.append({"zone_id": building.zone_id, "rate": rate})
			total_rate += rate
	if producers.is_empty() or total_rate <= 0.0:
		var fallback_zone: int = int(local_inventories.keys()[0]) if not local_inventories.is_empty() else 0
		var fallback: Dictionary = _ensure_inventory(fallback_zone)
		fallback[p_resource_id] = float(fallback.get(p_resource_id, 0.0)) + p_amount
		return
	for producer in producers:
		var inventory: Dictionary = _ensure_inventory(int(producer["zone_id"]))
		inventory[p_resource_id] = float(inventory.get(p_resource_id, 0.0)) + p_amount * float(producer["rate"]) / total_rate


func _remove_from_local_inventories(p_resource_id: String, p_amount: float) -> void:
	var remaining: float = p_amount
	var zone_ids: Array = local_inventories.keys()
	zone_ids.sort()
	for zone_id in zone_ids:
		var inventory: Dictionary = local_inventories[zone_id]
		var removed: float = minf(remaining, maxf(0.0, float(inventory.get(p_resource_id, 0.0))))
		inventory[p_resource_id] = maxf(0.0, float(inventory.get(p_resource_id, 0.0)) - removed)
		remaining -= removed
		if remaining <= 1e-7:
			break


func _match_civilization_totals(p_totals: Dictionary) -> void:
	for resource_id in p_totals:
		var represented: float = 0.0
		for inventory in local_inventories.values():
			represented += maxf(0.0, float(inventory.get(resource_id, 0.0)))
		for reserve in operation_reserves.values():
			represented += maxf(0.0, float((reserve.get("resources", {}) as Dictionary).get(resource_id, 0.0)))
		var difference: float = maxf(0.0, float(p_totals[resource_id])) - represented
		if difference > 1e-6:
			var fallback_zone: int = int(local_inventories.keys()[0]) if not local_inventories.is_empty() else 0
			var fallback: Dictionary = _ensure_inventory(fallback_zone)
			fallback[resource_id] = float(fallback.get(resource_id, 0.0)) + difference
		elif represented > float(p_totals[resource_id]) + 1e-6:
			_remove_from_local_inventories(str(resource_id), represented - float(p_totals[resource_id]))


func _initialize_networks() -> void:
	network_connections = {"road": [], "pipeline": [], "grid": []}
