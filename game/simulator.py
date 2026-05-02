"""游戏模拟器 - 状态更新逻辑"""
from typing import Dict, Any
from .environment import ThreeBodySimulation
from .entities import EntityManager
from .technology import TechTree, RESEARCH_BASIC, RESEARCH_APPLIED, RESEARCH_THEORETICAL
from .decision import DecisionManager
from .planet_zones import PlanetZoneManager
import numpy as np


class GameSimulator:
    """游戏模拟器 - 协调环境、实体、区域、科技和决策更新"""

    def __init__(self, config: dict = None):
        self.environment = ThreeBodySimulation()
        self.entities = EntityManager(config)
        self.tech_tree = TechTree()
        self.decision_manager = DecisionManager()
        self.planet_zones = PlanetZoneManager()
        self.time = 0.0
        self.paused = False
        self.game_over = False  # 游戏是否结束
        self.universe_name = "未命名宇宙"  # 宇宙名称（新建游戏时设置）
        self.last_autosave_day = -1  # 记录上次自动存档的天数
        self._init_zone_temperatures()

    def reset(self, config: dict = None):
        """重置游戏状态 - 用于开始新游戏（不重置 universe_name，由外部设置）"""
        self.environment = ThreeBodySimulation()
        self.entities = EntityManager(config)
        self.tech_tree = TechTree()
        self.decision_manager = DecisionManager()
        self.planet_zones = PlanetZoneManager()
        self.time = 0.0
        self.paused = False
        self.game_over = False
        self.last_autosave_day = -1
        self._init_zone_temperatures()

    def update(self, dt: float):
        """更新游戏状态"""
        if self.paused or self.game_over:
            return

        time_scale = self.environment.time_scale

        # 更新三体运动
        self.environment.update(dt)

        # 收集恒星数据（用于区域环境计算）
        stars_data = []
        planet_position = np.zeros(3)
        for star in self.environment.stars:
            stars_data.append({
                "position": star.position.copy(),
                "mass": star.mass,
                "is_planet": star.is_planet,
            })
            if star.is_planet:
                planet_position = star.position.copy()

        # 更新行星区域（自转 + 环境计算）
        self.planet_zones.update(dt, time_scale, stars_data, planet_position)

        # 获取全球平均环境参数（用于实体更新和主界面显示）
        avg_env = self.planet_zones.get_average_environment()

        # 也获取原始的环境参数（包含稳定性等非区域化数据）
        raw_env = self.environment.get_environment_params()

        # 合并：使用区域平均值覆盖温度/辐射/光照
        env_params = {
            "light_intensity": avg_env.get("light_intensity", raw_env.get("light_intensity", 0)),
            "heat_level": avg_env.get("light_intensity", 0) * 6.0,  # 兼容旧温度热等级逻辑
            "temperature": avg_env.get("temperature", raw_env.get("temperature", -273.15)),
            "radiation": avg_env.get("radiation", raw_env.get("radiation", 0)),
            "stability": raw_env.get("stability", 0),
        }

        # 更新实体（传入区域管理器进行逐区域建筑伤害）
        game_days_dt = dt * time_scale
        self.entities.update(env_params, zone_manager=self.planet_zones, dt=game_days_dt)

        # 研究建筑产出科技点数
        self._process_research_output(game_days_dt)

        # 更新决策冷却时间
        self.decision_manager.update_cooldowns(dt, time_scale)

        # 累计游戏时间
        self.time += dt * time_scale

    def _process_research_output(self, game_days_dt: float):
        """处理研究建筑的科技点数产出"""
        # 基础科研：人口 / 500 每天产出1点基础科研
        pop = self.entities.get_resource("population")
        basic_output = (pop / 500.0) * game_days_dt
        self.tech_tree.produce_research(RESEARCH_BASIC, basic_output)

        # 应用科研：每座活跃的实验室每天产出2点
        labs = self.entities.get_buildings_by_type("laboratory")
        for lab in labs:
            efficiency = lab.durability / lab.max_durability if lab.max_durability > 0 else 0
            self.tech_tree.produce_research(RESEARCH_APPLIED, 2.0 * efficiency * game_days_dt)

        # 理论科研：每座活跃的科学院每天产出1点
        academies = self.entities.get_buildings_by_type("academy")
        for academy in academies:
            efficiency = academy.durability / academy.max_durability if academy.max_durability > 0 else 0
            self.tech_tree.produce_research(RESEARCH_THEORETICAL, 1.0 * efficiency * game_days_dt)

    def get_state(self) -> Dict[str, Any]:
        """获取完整游戏状态"""
        # 从区域系统获取环境数据
        avg_env = self.planet_zones.get_average_environment()
        raw_env = self.environment.get_environment_params()

        merged_params = {
            "light_intensity": avg_env.get("light_intensity", 0),
            "heat_level": avg_env.get("light_intensity", 0) * 6.0,
            "temperature": avg_env.get("temperature", -273.15),
            "radiation": avg_env.get("radiation", 0),
            "stability": raw_env.get("stability", 0),
        }

        return {
            "time": self.time,
            "paused": self.paused,
            "game_over": self.game_over,
            "environment": {
                "stars": [
                    {
                        "position": star.position.tolist(),
                        "velocity": star.velocity.tolist(),
                        "color": star.color,
                        "radius": star.radius,
                        "mass": star.mass,
                        "is_planet": star.is_planet,
                        "trail": [p.tolist() for p in star.trail] if star.trail else []
                    }
                    for star in self.environment.stars
                ],
                "params": merged_params,
            },
            "entities": self.entities.get_state(),
            "technology": self.tech_tree.get_state(),
            "decision": self.decision_manager.get_state(),
            "planet_zones": {
                "rotation_angle": self.planet_zones.rotation_angle,
                "zones_summary": self.planet_zones.get_all_zones_summary(),
            },
        }

    def to_dict(self) -> Dict[str, Any]:
        """序列化游戏状态 - 用于保存游戏"""
        return {
            "time": self.time,
            "paused": self.paused,
            "game_over": self.game_over,
            "universe_name": self.universe_name,
            "stars": [
                {
                    "mass": star.mass,
                    "position": star.position.tolist(),
                    "velocity": star.velocity.tolist(),
                    "color": list(star.color),
                    "radius": star.radius,
                    "is_planet": star.is_planet,
                }
                for star in self.environment.stars
            ],
            "entities": self.entities.get_state(),
            "technology": self.tech_tree.get_state(),
            "decision": self.decision_manager.get_state(),
            "planet_zones": self.planet_zones.get_state(),
            "time_scale": self.environment.time_scale,
        }

    def from_dict(self, data: Dict[str, Any]):
        """从字典恢复游戏状态 - 用于加载存档"""
        import numpy as np
        from .environment import Star

        self.time = data.get("time", 0.0)
        self.paused = data.get("paused", False)
        self.game_over = data.get("game_over", False)
        self.universe_name = data.get("universe_name", "未命名宇宙")
        self.environment.time_scale = data.get("time_scale", 1.0)

        # 恢复星球状态
        stars_data = data.get("stars", [])
        if stars_data:
            self.environment.stars = []
            for sd in stars_data:
                star = Star(
                    mass=sd["mass"],
                    position=np.array(sd["position"]),
                    velocity=np.array(sd["velocity"]),
                    color=tuple(sd["color"]),
                    radius=sd["radius"],
                    is_planet=sd.get("is_planet", False),
                )
                self.environment.stars.append(star)

        # 恢复实体状态
        if "entities" in data:
            self.entities.load_state(data["entities"])

        # 恢复科技状态
        if "technology" in data:
            tech_data = data["technology"]
            if isinstance(tech_data, dict):
                self.tech_tree.load_state(tech_data)
            elif isinstance(tech_data, list):
                self.tech_tree.load_state({"unlocked": tech_data})

        # 恢复决策状态
        if "decision" in data:
            self.decision_manager.load_state(data["decision"])
        elif "policy" in data:
            # 向后兼容旧版政策数据
            old_policy = data["policy"]
            self.decision_manager.load_state({
                "current_state": old_policy.get("current_state", "normal"),
                "enacted_history": old_policy.get("enacted_policies", []),
            })

        # 恢复区域数据
        if "planet_zones" in data:
            self.planet_zones.load_state(data["planet_zones"])

    def toggle_pause(self):
        """切换暂停状态"""
        self.paused = not self.paused

    def set_time_scale(self, scale: float):
        """设置时间流逝速度"""
        self.environment.time_scale = max(0.1, min(10.0, scale))

    def _init_zone_temperatures(self):
        """在游戏开始时校准宜居偏移并将区域温度初始化为目标温度"""
        stars_data = []
        planet_position = np.zeros(3)
        for star in self.environment.stars:
            stars_data.append({
                "position": star.position.copy(),
                "mass": star.mass,
                "is_planet": star.is_planet,
            })
            if star.is_planet:
                planet_position = star.position.copy()

        # 先不带偏移计算一次，获取原始平均温度
        self.planet_zones.habitable_offset = 0.0
        self.planet_zones.initialize_temperatures(stars_data, planet_position)

        # 校准偏移使全球平均温度为 20°C
        avg = self.planet_zones.get_average_environment()
        self.planet_zones.habitable_offset = 20.0 - avg["temperature"]

        # 用校准后的偏移重新计算初始温度
        self.planet_zones.initialize_temperatures(stars_data, planet_position)