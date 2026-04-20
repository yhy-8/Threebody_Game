"""实体系统 - 人物、建筑、资源管理"""
from dataclasses import dataclass, field
from typing import List, Optional
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
    name: str
    building_type: str  # "mine", "power", "habitat", etc.
    level: int = 1
    position: tuple = (0, 0)
    production: dict = field(default_factory=dict)  # 产出
    consumption: dict = field(default_factory=dict)  # 消耗

    def get_output(self) -> dict:
        """获取产出"""
        output = {}
        for resource, amount in self.production.items():
            output[resource] = amount * self.level
        return output


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
        self.population = 1250
        self.global_efficiency = 1.0
        self._init_defaults()

    def _init_defaults(self):
        self.add_resource(Resource("minerals", 1000, 10000, 1.0))
        self.add_resource(Resource("energy", 500, 5000, 0.5))
        self.add_resource(Resource("food", 800, 8000, 0.8))

    def add_person(self, person: Person):
        self.people.append(person)

    def add_building(self, building: Building):
        self.buildings.append(building)

    def add_resource(self, resource: Resource):
        self.resources[resource.name] = resource

    def update(self, env_params: dict):
        """更新所有实体状态"""
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
            for resource, amount in building.consumption.items():
                if resource in self.resources:
                    self.resources[resource].consume(amount * building.level)

        # 添加产出到资源
        for resource, amount in total_production.items():
            if resource in self.resources:
                self.resources[resource].add(amount)

    def get_state(self) -> dict:
        """获取实体状态摘要"""
        return {
            "people_count": self.population,
            "buildings_count": len(self.buildings),
            "resources": {name: res.amount for name, res in self.resources.items()},
            "avg_efficiency": self.global_efficiency
        }