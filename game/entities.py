"""实体系统 - 人物、建筑、资源管理

资源体系：
  矿物: iron(铁), copper(铜), rare_mineral(稀有矿物)
  能源: algae_fuel(藻类燃料), fossil_fuel(化石燃料), electricity(电力/kW)
  食物: food
  
人口管理:
  PopulationManager 管理人口总数与岗位分配。
  设施决定产出上限，人力决定实际产出。
"""
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Tuple
from enum import Enum


class EntityType(Enum):
    """实体类型"""
    PERSON = "person"
    BUILDING = "building"
    RESOURCE = "resource"


# ── 资源名称映射（用于 UI 显示） ─────────────────────────────────
RESOURCE_DISPLAY_NAMES: Dict[str, str] = {
    "iron": "铁矿",
    "copper": "铜矿",
    "rare_mineral": "稀有矿物",
    "algae_fuel": "藻类燃料",
    "fossil_fuel": "化石燃料",
    "electricity": "电力",
    "food": "食物",
}

RESOURCE_COLORS: Dict[str, Tuple[int, int, int]] = {
    "iron": (180, 180, 200),
    "copper": (220, 160, 100),
    "rare_mineral": (180, 120, 255),
    "algae_fuel": (100, 200, 120),
    "fossil_fuel": (160, 140, 100),
    "electricity": (255, 220, 80),
    "food": (100, 255, 150),
}

# 资源分组 — 用于 UI 面板布局
RESOURCE_GROUPS = {
    "矿物": ["iron", "copper", "rare_mineral"],
    "能源": ["algae_fuel", "fossil_fuel", "electricity"],
    "食物": ["food"],
}


@dataclass
class Resource:
    """资源"""
    name: str
    display_name: str = ""
    amount: float = 0.0
    max_storage: float = 10000.0

    def __post_init__(self):
        if not self.display_name:
            self.display_name = RESOURCE_DISPLAY_NAMES.get(self.name, self.name)

    def add(self, amount: float):
        self.amount = min(self.max_storage, self.amount + amount)

    def consume(self, amount: float) -> bool:
        """尝试消耗资源，返回是否成功"""
        if self.amount >= amount:
            self.amount -= amount
            return True
        return False


# ── 岗位类型 ──────────────────────────────────────────────────────
JOB_TYPES = {
    "mining_iron": "铁矿工",
    "mining_copper": "铜矿工",
    "mining_rare": "稀有矿工",
    "farming": "农民",
    "algae_collect": "藻类采集",
    "fossil_mining": "化石燃料工",
    "power_worker": "发电工",
    "researcher": "研究员",
    "breeding": "生育",
}


class PopulationManager:
    """人口管理器 — 管理人口总数与岗位分配
    
    人口通过 '生育' 岗位增长；自动化科技可提高单人效率。
    """

    def __init__(self, initial_population: int = 100):
        self.total: int = initial_population
        # 岗位分配: { "mining_iron": 5, ... }
        self.assignments: Dict[str, int] = {}
        # 各岗位对应的区域 { "mining_iron": {zone_id: count, ...}, ... }
        self.zone_assignments: Dict[str, Dict[int, int]] = {}
        # 人口增长基础参数
        self.base_growth_per_breeder: float = 0.05  # 每个生育人口每天增长 0.05 人
        self.natural_growth_rate: float = 0.001  # 闲置人口微量自然增长（每人每天）
        # 自动化效率倍率（科技解锁后提升）
        self.automation_multiplier: float = 1.0
        # 食物消耗：每人每天消耗食物
        self.food_per_person_per_day: float = 0.1
        # 人口累积（用于非整数增长）
        self._growth_accumulator: float = 0.0

    def get_idle(self) -> int:
        """获取未分配人口"""
        assigned = sum(self.assignments.values())
        return max(0, self.total - assigned)

    def get_assigned(self, job: str) -> int:
        """获取某岗位的分配人数"""
        return self.assignments.get(job, 0)

    def get_total_assigned(self) -> int:
        """获取已分配总人数"""
        return sum(self.assignments.values())

    def assign(self, job: str, count: int, zone_id: int = -1) -> Tuple[bool, str]:
        """分配人口到岗位
        
        Args:
            job: 岗位类型
            count: 分配人数
            zone_id: 工作区域（-1 表示不绑定区域）
        """
        if job not in JOB_TYPES:
            return False, f"未知岗位类型: {job}"
        if count <= 0:
            return False, "分配人数必须大于0"
        idle = self.get_idle()
        if count > idle:
            return False, f"闲置人口不足（可用: {idle}，需求: {count}）"

        self.assignments[job] = self.assignments.get(job, 0) + count

        # 区域关联
        if zone_id >= 0:
            if job not in self.zone_assignments:
                self.zone_assignments[job] = {}
            self.zone_assignments[job][zone_id] = self.zone_assignments[job].get(zone_id, 0) + count

        return True, f"已分配 {count} 人到 {JOB_TYPES[job]}"

    def unassign(self, job: str, count: int, zone_id: int = -1) -> Tuple[bool, str]:
        """从岗位撤回人口"""
        current = self.assignments.get(job, 0)
        if count > current:
            return False, f"当前该岗位只有 {current} 人"

        self.assignments[job] = current - count
        if self.assignments[job] <= 0:
            del self.assignments[job]

        # 更新区域关联
        if zone_id >= 0 and job in self.zone_assignments:
            zone_count = self.zone_assignments[job].get(zone_id, 0)
            self.zone_assignments[job][zone_id] = max(0, zone_count - count)
            if self.zone_assignments[job][zone_id] <= 0:
                del self.zone_assignments[job][zone_id]
            if not self.zone_assignments[job]:
                del self.zone_assignments[job]

        return True, f"已从 {JOB_TYPES[job]} 撤回 {count} 人"

    def get_workers_at_zone(self, job: str, zone_id: int) -> int:
        """获取某岗位在某区域的工人数"""
        return self.zone_assignments.get(job, {}).get(zone_id, 0)

    def update(self, dt_days: float, food_available: float) -> Dict[str, float]:
        """更新人口增长
        
        Args:
            dt_days: 游戏天数间隔
            food_available: 当前可用食物
            
        Returns:
            消耗信息 {"food_consumed": float, "growth": float}
        """
        # 食物消耗
        food_needed = self.total * self.food_per_person_per_day * dt_days
        food_consumed = min(food_needed, food_available)
        food_satisfaction = food_consumed / max(food_needed, 0.001)

        # 如果食物严重不足，人口减少
        if food_satisfaction < 0.5:
            starvation = (0.5 - food_satisfaction) * self.total * 0.01 * dt_days
            self.total = max(1, int(self.total - starvation))

        # 生育人口增长
        breeders = self.get_assigned("breeding")
        growth = breeders * self.base_growth_per_breeder * dt_days * food_satisfaction

        # 闲置人口微量自然增长
        idle = self.get_idle()
        growth += idle * self.natural_growth_rate * dt_days * food_satisfaction

        # 累积并转换为整数增长
        self._growth_accumulator += growth
        int_growth = int(self._growth_accumulator)
        if int_growth > 0:
            self.total += int_growth
            self._growth_accumulator -= int_growth

        return {
            "food_consumed": food_consumed,
            "growth": growth,
        }

    def get_state(self) -> dict:
        """序列化"""
        return {
            "total": self.total,
            "assignments": dict(self.assignments),
            "zone_assignments": {
                job: dict(zones)
                for job, zones in self.zone_assignments.items()
            },
            "automation_multiplier": self.automation_multiplier,
            "growth_accumulator": self._growth_accumulator,
        }

    def load_state(self, data: dict):
        """反序列化"""
        self.total = data.get("total", 100)
        self.assignments = data.get("assignments", {})
        # zone_assignments 的 key 是 zone_id (int)，JSON 序列化会变成字符串
        raw_za = data.get("zone_assignments", {})
        self.zone_assignments = {}
        for job, zones in raw_za.items():
            self.zone_assignments[job] = {int(k): v for k, v in zones.items()}
        self.automation_multiplier = data.get("automation_multiplier", 1.0)
        self._growth_accumulator = data.get("growth_accumulator", 0.0)


@dataclass
class Building:
    """建筑"""
    id: int = 0               # 唯一ID
    name: str = ""
    building_type: str = ""   # "iron_mine", "farm", "power_plant", etc.
    level: int = 1
    zone_id: int = -1         # 所在区域ID（-1 表示未分配区域）

    # ── 人力驱动产出模型 ──
    worker_capacity: int = 0          # 最大工人容量
    assigned_workers: int = 0         # 当前分配工人数
    per_worker_output: dict = field(default_factory=dict)  # 每个工人产出/天
    consumption: dict = field(default_factory=dict)        # 建筑本身的日消耗

    # 耐久度系统
    durability: float = 100.0
    max_durability: float = 100.0

    # 抗性（可通过科技强化）
    heat_resistance: float = 60.0      # 温度超过此值时开始受损 (℃)
    cold_resistance: float = -80.0     # 温度低于此值时开始受损 (℃)
    radiation_resistance: float = 5.0  # 辐射超过此值时开始受损

    # 状态
    active: bool = True       # 是否活跃（耐久为0时变为False）
    destroyed: bool = False   # 是否已被摧毁

    def get_output(self, automation_multiplier: float = 1.0) -> dict:
        """获取产出 — 由人力驱动，设施决定上限
        
        产出 = min(assigned_workers, worker_capacity) × per_worker_output × 耐久度% × 自动化倍率
        
        Args:
            automation_multiplier: 自动化科技带来的效率倍率
        """
        if not self.active or self.destroyed:
            return {}

        if self.worker_capacity <= 0:
            # 无需工人的建筑（如庇护所），直接产出空字典
            return {}

        effective_workers = min(self.assigned_workers, self.worker_capacity)
        if effective_workers <= 0:
            return {}

        durability_ratio = self.durability / self.max_durability if self.max_durability > 0 else 0
        output = {}
        for resource, per_worker in self.per_worker_output.items():
            output[resource] = effective_workers * per_worker * durability_ratio * automation_multiplier
        return output

    def get_consumption(self) -> dict:
        """获取建筑消耗 — 只要建筑活跃就消耗（不依赖工人数）"""
        if not self.active or self.destroyed:
            return {}
        return dict(self.consumption)

    def get_saturation(self) -> float:
        """获取工人饱和度（0.0 ~ 1.0）"""
        if self.worker_capacity <= 0:
            return 1.0  # 无需工人
        return min(1.0, self.assigned_workers / self.worker_capacity)

    def take_damage(self, amount: float):
        """受到环境伤害"""
        self.durability = max(0, self.durability - amount)
        if self.durability <= 0:
            self.active = False
            self.destroyed = True

    def repair(self, amount: float):
        """修复"""
        if self.destroyed:
            return
        self.durability = min(self.max_durability, self.durability + amount)
        if self.durability > 0:
            self.active = True

    def apply_environment_damage(self, zone_temp: float, zone_radiation: float, dt: float):
        """根据所在区域的环境计算伤害

        Args:
            zone_temp: 区域温度 (℃)
            zone_radiation: 区域辐射度
            dt: 帧间隔（游戏天数）
        """
        damage = 0.0

        # 高温伤害
        if zone_temp > self.heat_resistance:
            excess = zone_temp - self.heat_resistance
            damage += excess * 0.1 * dt  # 每超1度每天0.1点伤害

        # 低温伤害
        if zone_temp < self.cold_resistance:
            excess = self.cold_resistance - zone_temp
            damage += excess * 0.05 * dt  # 严寒伤害略低

        # 辐射伤害
        if zone_radiation > self.radiation_resistance:
            excess = zone_radiation - self.radiation_resistance
            damage += excess * 0.2 * dt

        if damage > 0:
            self.take_damage(damage)


class EntityManager:
    """实体管理器 — 管理建筑、资源和人口"""

    def __init__(self):
        self.buildings: List[Building] = []
        self.resources: dict = {}
        self.population: PopulationManager = PopulationManager(100)
        self.global_efficiency = 1.0
        self._init_defaults()

    def _init_defaults(self):
        """初始化默认资源 — 不含自然恢复"""
        # 矿物
        self.add_resource(Resource("iron", amount=200, max_storage=5000))
        self.add_resource(Resource("copper", amount=30, max_storage=3000))
        self.add_resource(Resource("rare_mineral", amount=0, max_storage=1000))
        # 能源
        self.add_resource(Resource("algae_fuel", amount=100, max_storage=3000))
        self.add_resource(Resource("fossil_fuel", amount=0, max_storage=3000))
        self.add_resource(Resource("electricity", amount=0, max_storage=500))
        # 食物
        self.add_resource(Resource("food", amount=300, max_storage=8000))

    def add_building(self, building: Building):
        self.buildings.append(building)

    def remove_building(self, building_id: int):
        """移除建筑"""
        self.buildings = [b for b in self.buildings if b.id != building_id]

    def get_building(self, building_id: int) -> Optional[Building]:
        """根据ID获取建筑"""
        for b in self.buildings:
            if b.id == building_id:
                return b
        return None

    def get_buildings_in_zone(self, zone_id: int) -> List[Building]:
        """获取指定区域的所有建筑"""
        return [b for b in self.buildings if b.zone_id == zone_id]

    def add_resource(self, resource: Resource):
        self.resources[resource.name] = resource

    def get_resource(self, name: str) -> float:
        """获取资源数量 — 兼容旧接口: 'population' 转发到 PopulationManager"""
        if name == "population":
            return float(self.population.total)
        res = self.resources.get(name)
        return res.amount if res else 0.0

    def consume_resource(self, name: str, amount: float) -> bool:
        """消耗指定资源"""
        if name == "population":
            return False  # 人口不能被直接消耗
        res = self.resources.get(name)
        if res:
            return res.consume(amount)
        return False

    def produce_resource(self, name: str, amount: float):
        """增加指定资源"""
        res = self.resources.get(name)
        if res:
            res.add(amount)

    def get_building_count(self) -> int:
        return len([b for b in self.buildings if not b.destroyed])

    def get_active_building_count(self) -> int:
        """获取活跃（未损毁）的建筑数量"""
        return len([b for b in self.buildings if b.active and not b.destroyed])

    def get_buildings_by_type(self, building_type: str) -> List[Building]:
        """获取指定类型的所有活跃建筑"""
        return [b for b in self.buildings
                if b.building_type == building_type and b.active and not b.destroyed]

    def get_electricity_balance(self) -> Tuple[float, float]:
        """获取电力收支: (总发电量/天, 总耗电量/天)
        
        Returns:
            (generation, consumption) per day
        """
        generation = 0.0
        consumption = 0.0

        for building in self.buildings:
            if not building.active or building.destroyed:
                continue
            output = building.get_output(self.population.automation_multiplier)
            generation += output.get("electricity", 0.0)
            cons = building.get_consumption()
            consumption += cons.get("electricity", 0.0)

        return generation, consumption

    def update(self, env_params: dict, zone_manager=None, dt: float = 0.016):
        """更新所有实体状态

        Args:
            env_params: 全球平均环境参数
            zone_manager: 行星区域管理器（用于逐区域计算建筑伤害）
            dt: 帧间隔（游戏天数）
        """
        # 宏观环境对文明整体的影响
        heat = env_params.get("heat_level", 0.5)
        if heat > 0.8:
            self.global_efficiency = max(0.5, self.global_efficiency - 0.01)
        elif heat < 0.2:
            self.global_efficiency = max(0.3, self.global_efficiency - 0.02)
        else:
            self.global_efficiency = min(1.0, self.global_efficiency + 0.01)

        # 建筑逐区域环境伤害（耐久度下降仅由环境伤害导致，不自然衰减）
        if zone_manager:
            for building in self.buildings:
                if building.destroyed or building.zone_id < 0:
                    continue
                zone = zone_manager.get_zone(building.zone_id)
                if zone:
                    building.apply_environment_damage(
                        zone.temperature, zone.radiation, dt
                    )

        # 建筑产出和消耗（人力驱动）
        self._process_buildings(dt)

        # 人口更新（食物消耗 + 增长）
        food_available = self.get_resource("food")
        pop_result = self.population.update(dt, food_available)
        food_consumed = pop_result.get("food_consumed", 0.0)
        if food_consumed > 0:
            self.consume_resource("food", food_consumed)

    def _process_buildings(self, dt: float = 1.0):
        """处理建筑产出和消耗 — 人力驱动模型
        
        电力平衡检查：如果总发电量 < 总耗电量，所有建筑效率下降。
        """
        # 计算电力平衡
        gen, cons = self.get_electricity_balance()
        power_ratio = min(1.0, gen / max(cons, 0.001)) if cons > 0 else 1.0

        # 先扣消耗
        for building in self.buildings:
            building_cons = building.get_consumption()
            for resource, amount in building_cons.items():
                daily_amount = amount * dt
                if resource in self.resources:
                    self.resources[resource].consume(daily_amount)

        # 再加产出（受电力平衡影响）
        for building in self.buildings:
            output = building.get_output(self.population.automation_multiplier)
            for resource, amount in output.items():
                daily_amount = amount * dt
                # 如果是非电力建筑且需要电力，受 power_ratio 影响
                if resource != "electricity":
                    daily_amount *= power_ratio
                if resource in self.resources:
                    self.resources[resource].add(daily_amount)

    def get_state(self) -> dict:
        """获取实体状态摘要"""
        return {
            "buildings_count": self.get_building_count(),
            "active_buildings": self.get_active_building_count(),
            "resources": {name: res.amount for name, res in self.resources.items()},
            "population": self.population.get_state(),
            "avg_efficiency": self.global_efficiency,
            "buildings": [
                {
                    "id": b.id,
                    "name": b.name,
                    "type": b.building_type,
                    "zone_id": b.zone_id,
                    "durability": b.durability,
                    "max_durability": b.max_durability,
                    "active": b.active,
                    "destroyed": b.destroyed,
                    "worker_capacity": b.worker_capacity,
                    "assigned_workers": b.assigned_workers,
                    "per_worker_output": dict(b.per_worker_output),
                    "consumption": dict(b.consumption),
                }
                for b in self.buildings
            ],
        }

    def load_state(self, data: dict):
        """恢复实体状态"""
        self.buildings.clear()
        self.global_efficiency = data.get("avg_efficiency", 1.0)
        
        # 恢复资源
        for name, amount in data.get("resources", {}).items():
            if name in self.resources:
                self.resources[name].amount = amount
                
        # 恢复人口
        if "population" in data:
            self.population.load_state(data["population"])
            
        # 恢复建筑
        for b_data in data.get("buildings", []):
            b = Building(
                id=b_data.get("id", 0),
                name=b_data.get("name", ""),
                building_type=b_data.get("type", ""),
                zone_id=b_data.get("zone_id", -1),
                durability=b_data.get("durability", 100.0),
                max_durability=b_data.get("max_durability", 100.0),
                active=b_data.get("active", True),
                destroyed=b_data.get("destroyed", False),
                worker_capacity=b_data.get("worker_capacity", 0),
                assigned_workers=b_data.get("assigned_workers", 0),
                per_worker_output=b_data.get("per_worker_output", {}),
                consumption=b_data.get("consumption", {})
            )
            self.buildings.append(b)