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


# 移除全局抽象的 JOB_TYPES，人员直接分配给具体建筑

class PopulationManager:
    """人口管理器 — 管理人口总数与岗位分配
    
    人口通过 '生育' 岗位增长；自动化科技可提高单人效率。
    """

    def __init__(self, initial_population: int = 100):
        self.total: int = initial_population
        self.breeders: int = 0  # 专门从事生育的人口

        # 人口增长基础参数
        self.base_growth_per_breeder: float = 0.05  # 每个生育人口每天增长 0.05 人
        self.natural_growth_rate: float = 0.001  # 闲置人口微量自然增长（每人每天）
        # 自动化效率倍率（科技解锁后提升）
        self.automation_multiplier: float = 1.0
        # 食物消耗：每人每天消耗食物
        self.food_per_person_per_day: float = 0.1
        # 人口累积（用于非整数增长）
        self._growth_accumulator: float = 0.0

    def get_idle(self, total_building_workers: int) -> int:
        """获取未分配人口"""
        return max(0, self.total - self.breeders - total_building_workers)

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
        growth = self.breeders * self.base_growth_per_breeder * dt_days * food_satisfaction

        # 闲置人口微量自然增长 (假设为总人口的一定比例，但不作为主要动力)
        # 现在不需要专门计算闲置了，简单点：
        idle = max(0, self.total - self.breeders)
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
            "breeders": self.breeders,
            "automation_multiplier": self.automation_multiplier,
            "growth_accumulator": self._growth_accumulator,
        }

    def load_state(self, data: dict):
        """反序列化"""
        self.total = data.get("total", 100)
        self.breeders = data.get("breeders", 0)
        # 向后兼容：将原来 assignments 里的 breeding 转化过来
        if "assignments" in data:
            self.breeders += data["assignments"].get("breeding", 0)
            
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

    def __init__(self, config: dict = None):
        self.buildings: List[Building] = []
        self.resources: dict = {}
        
        initial_pop = 100
        if config and "initial_entities" in config:
            initial_pop = config["initial_entities"].get("population", 100)
            
        self.population: PopulationManager = PopulationManager(initial_pop)
        self.global_efficiency = 1.0
        self._init_defaults(config)

    def _init_defaults(self, config: dict = None):
        """初始化默认资源"""
        default_res = {
            "iron": 200, "copper": 30, "rare_mineral": 0,
            "algae_fuel": 100, "fossil_fuel": 0, "electricity": 0,
            "food": 300
        }
        max_storage_map = {
            "iron": 5000, "copper": 3000, "rare_mineral": 1000,
            "algae_fuel": 3000, "fossil_fuel": 3000, "electricity": 500,
            "food": 8000
        }
        
        if config and "initial_entities" in config and "resources" in config["initial_entities"]:
            res_list = config["initial_entities"]["resources"]
            if isinstance(res_list, list):
                for res_item in res_list:
                    name = res_item.get("name")
                    if name in default_res:
                        default_res[name] = res_item.get("amount", default_res[name])
                        if "max_storage" in res_item:
                            max_storage_map[name] = res_item["max_storage"]

        for k, v in default_res.items():
            self.add_resource(Resource(k, amount=v, max_storage=max_storage_map.get(k, 1000)))

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

    def get_building(self, building_id: int) -> Optional[Building]:
        """获取建筑"""
        for b in self.buildings:
            if b.id == building_id:
                return b
        return None

    # ── 人口分配管理 ──
    
    def get_total_building_workers(self) -> int:
        """获取分配在所有建筑中的总工人数"""
        return sum(b.assigned_workers for b in self.buildings if b.active and not b.destroyed)

    def get_idle_population(self) -> int:
        """获取当前闲置人口"""
        return self.population.get_idle(self.get_total_building_workers())

    def assign_worker_to_building(self, building_id: int, count: int) -> Tuple[bool, str]:
        """向特定建筑分配工人"""
        b = self.get_building(building_id)
        if not b:
            return False, "建筑不存在"
        if not b.active or b.destroyed:
            return False, "建筑已停用或损毁"
        
        idle = self.get_idle_population()
        if count > idle:
            return False, f"闲置人口不足（需要 {count}，仅剩 {idle}）"
            
        space = b.worker_capacity - b.assigned_workers
        if count > space:
            return False, f"建筑容量不足（仅剩 {space} 个空余岗位）"
            
        b.assigned_workers += count
        return True, f"已分配 {count} 人到 {b.name}"

    def unassign_worker_from_building(self, building_id: int, count: int) -> Tuple[bool, str]:
        """从特定建筑撤回工人"""
        b = self.get_building(building_id)
        if not b:
            return False, "建筑不存在"
            
        if count > b.assigned_workers:
            return False, f"当前建筑只有 {b.assigned_workers} 人"
            
        b.assigned_workers -= count
        return True, f"已从 {b.name} 撤回 {count} 人"

    def assign_breeders(self, count: int) -> Tuple[bool, str]:
        """分配生育人员"""
        idle = self.get_idle_population()
        if count > idle:
            return False, f"闲置人口不足（需要 {count}，仅剩 {idle}）"
        self.population.breeders += count
        return True, f"已分配 {count} 人生育"

    def unassign_breeders(self, count: int) -> Tuple[bool, str]:
        """撤回生育人员"""
        if count > self.population.breeders:
            return False, f"当前只有 {self.population.breeders} 人在生育"
        self.population.breeders -= count
        return True, f"已撤回 {count} 名生育人员"

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