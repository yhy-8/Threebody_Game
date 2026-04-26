"""实体系统 - 人物、建筑、资源管理"""
from dataclasses import dataclass, field
from typing import List, Optional, Dict
from enum import Enum


class EntityType(Enum):
    """实体类型"""
    PERSON = "person"
    BUILDING = "building"
    RESOURCE = "resource"


@dataclass
class Person:
    """人物"""
    name: str
    role: str = "worker"
    health: float = 100.0
    efficiency: float = 1.0  # 工作效率
    position: tuple = (0, 0)  # 2D位置

    def update(self, env_params: dict):
        """根据环境更新状态"""
        # 热量影响效率
        heat = env_params.get("heat_level", 0.5)
        if heat > 0.8:
            self.efficiency = max(0.5, self.efficiency - 0.1)
        elif heat < 0.2:
            self.efficiency = max(0.3, self.efficiency - 0.2)
        else:
            self.efficiency = min(1.0, self.efficiency + 0.05)

        # 稳定性影响健康
        stability = env_params.get("stability", 0.5)
        if stability < 0.3:
            self.health = max(0, self.health - 0.5)


@dataclass
class Building:
    """建筑"""
    id: int = 0               # 唯一ID
    name: str = ""
    building_type: str = ""   # "mine", "power_plant", "laboratory", etc.
    level: int = 1
    zone_id: int = -1         # 所在区域ID（-1 表示未分配区域）
    production: dict = field(default_factory=dict)   # 产出
    consumption: dict = field(default_factory=dict)  # 消耗

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

    def get_output(self) -> dict:
        """获取产出"""
        if not self.active or self.destroyed:
            return {}
        output = {}
        # 耐久度影响产出效率
        efficiency = self.durability / self.max_durability if self.max_durability > 0 else 0
        for resource, amount in self.production.items():
            output[resource] = amount * self.level * efficiency
        return output

    def get_consumption(self) -> dict:
        """获取消耗"""
        if not self.active or self.destroyed:
            return {}
        result = {}
        for resource, amount in self.consumption.items():
            result[resource] = amount * self.level
        return result

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


@dataclass
class Resource:
    """资源"""
    name: str
    amount: float
    max_storage: float = 10000.0
    regeneration_rate: float = 0.0  # 自然恢复速率

    def add(self, amount: float):
        self.amount = min(self.max_storage, self.amount + amount)

    def consume(self, amount: float) -> bool:
        """尝试消耗资源，返回是否成功"""
        if self.amount >= amount:
            self.amount -= amount
            return True
        return False


class EntityManager:
    """实体管理器"""

    def __init__(self):
        self.people: List[Person] = []
        self.buildings: List[Building] = []
        self.resources: dict = {}
        self.global_efficiency = 1.0
        self._init_defaults()

    def _init_defaults(self):
        self.add_resource(Resource("minerals", 1000, 10000, 1.0))
        self.add_resource(Resource("energy", 500, 5000, 0.5))
        self.add_resource(Resource("food", 800, 8000, 0.8))
        self.add_resource(Resource("population", 1250, 1000000, 1.0))

    def add_person(self, person: Person):
        self.people.append(person)

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
        """获取资源数量"""
        res = self.resources.get(name)
        return res.amount if res else 0.0

    def consume_resource(self, name: str, amount: float) -> bool:
        """消耗指定资源"""
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

    def update(self, env_params: dict, zone_manager=None, dt: float = 0.016):
        """更新所有实体状态

        Args:
            env_params: 全球平均环境参数
            zone_manager: 行星区域管理器（用于逐区域计算建筑伤害）
            dt: 帧间隔
        """
        # 更新人物
        for person in self.people:
            person.update(env_params)

        # 宏观环境对文明整体的影响
        heat = env_params.get("heat_level", 0.5)
        if heat > 0.8:
            self.global_efficiency = max(0.5, self.global_efficiency - 0.01)
        elif heat < 0.2:
            self.global_efficiency = max(0.3, self.global_efficiency - 0.02)
        else:
            self.global_efficiency = min(1.0, self.global_efficiency + 0.01)

        # 自然恢复资源
        for resource in self.resources.values():
            if resource.regeneration_rate > 0:
                resource.add(resource.regeneration_rate)

        # 建筑逐区域环境伤害
        if zone_manager:
            for building in self.buildings:
                if building.destroyed or building.zone_id < 0:
                    continue
                zone = zone_manager.get_zone(building.zone_id)
                if zone:
                    building.apply_environment_damage(
                        zone.temperature, zone.radiation, dt
                    )

        # 建筑产出和消耗
        self._process_buildings()

    def _process_buildings(self):
        """处理建筑产出和消耗"""
        # 先收集所有产出
        total_production = {}
        for building in self.buildings:
            for resource, amount in building.get_output().items():
                total_production[resource] = total_production.get(resource, 0) + amount

        # 应用消耗
        for building in self.buildings:
            for resource, amount in building.get_consumption().items():
                if resource in self.resources:
                    self.resources[resource].consume(amount)

        # 添加产出到资源
        for resource, amount in total_production.items():
            if resource in self.resources:
                self.resources[resource].add(amount)

    def get_state(self) -> dict:
        """获取实体状态摘要"""
        return {
            "buildings_count": self.get_building_count(),
            "active_buildings": self.get_active_building_count(),
            "resources": {name: res.amount for name, res in self.resources.items()},
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
                }
                for b in self.buildings
            ],
        }