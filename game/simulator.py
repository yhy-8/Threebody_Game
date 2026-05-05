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
        self._config = config or {}
        self._env_config = self._config.get("environment", {})
        self.environment = ThreeBodySimulation()
        self.entities = EntityManager(config)
        self.tech_tree = TechTree()
        self.decision_manager = DecisionManager()
        self.planet_zones = PlanetZoneManager(self._env_config)
        self.time = 0.0
        self.paused = False
        self.game_over = False  # 游戏是否结束
        self.universe_name = "未命名宇宙"  # 宇宙名称（新建游戏时设置）
        self.last_autosave_day = -1  # 记录上次自动存档的天数
        # 科技点数每日产出速率（用于 UI 显示）
        self.research_output_rate: Dict[str, float] = {
            RESEARCH_BASIC: 0.0,
            RESEARCH_APPLIED: 0.0,
            RESEARCH_THEORETICAL: 0.0,
        }
        self._init_zone_temperatures()

    def reset(self, config: dict = None):
        """重置游戏状态 - 用于开始新游戏（不重置 universe_name，由外部设置）"""
        self.environment = ThreeBodySimulation()
        self.entities = EntityManager(config)
        self.tech_tree = TechTree()
        self.decision_manager = DecisionManager()
        self._config = config or {}
        self._env_config = self._config.get("environment", {})
        self.planet_zones = PlanetZoneManager(self._env_config)
        self.time = 0.0
        self.paused = False
        self.game_over = False
        self.last_autosave_day = -1
        self.research_output_rate = {
            RESEARCH_BASIC: 0.0,
            RESEARCH_APPLIED: 0.0,
            RESEARCH_THEORETICAL: 0.0,
        }
        self._init_zone_temperatures()

    def update(self, dt: float):
        """更新游戏状态"""
        if self.paused or self.game_over:
            return

        time_scale = self.environment.time_scale
        dehydrated = self.decision_manager.current_state.value == "dehydrated"

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
        self.entities.update(env_params, zone_manager=self.planet_zones, dt=game_days_dt, dehydrated=dehydrated)

        # 研究建筑产出科技点数
        self._process_research_output(game_days_dt)

        # 脱水状态下：库存人口环境损耗 + 暴露人口环境损耗
        if dehydrated:
            self._process_storage_damage(game_days_dt)

        # 更新决策冷却时间
        self.decision_manager.update_cooldowns(dt, time_scale)

        # 累计游戏时间
        self.time += dt * time_scale

    def _process_research_output(self, game_days_dt: float):
        """处理研究建筑的科技点数产出"""
        dehydrated = self.decision_manager.current_state.value == "dehydrated"
        dehydrate_mult = 0.1 if dehydrated else 1.0

        # 累计本帧产出（用于 UI 显示产出速率）
        frame_output = {RESEARCH_BASIC: 0.0, RESEARCH_APPLIED: 0.0, RESEARCH_THEORETICAL: 0.0}

        # 基础科研：人口 / 500 每天产出1点基础科研
        pop = self.entities.get_resource("population")
        basic_output = (pop / 500.0) * dehydrate_mult * game_days_dt
        self.tech_tree.produce_research(RESEARCH_BASIC, basic_output)
        frame_output[RESEARCH_BASIC] += (pop / 500.0) * dehydrate_mult

        # 研究院：每座活跃研究院每天产出1点基础科研（受工人饱和度、耐久度、区域效率影响）
        institutes = self.entities.get_buildings_by_type("research_institute")
        for inst in institutes:
            durability_ratio = inst.durability / inst.max_durability if inst.max_durability > 0 else 0
            worker_ratio = inst.get_saturation()
            zone_eff = 1.0
            if inst.zone_id >= 0:
                zone = self.planet_zones.get_zone(inst.zone_id)
                if zone:
                    zone_eff = zone.get_work_efficiency()
            efficiency = durability_ratio * worker_ratio * zone_eff * dehydrate_mult
            output = 1.0 * efficiency * game_days_dt
            self.tech_tree.produce_research(RESEARCH_BASIC, output)
            frame_output[RESEARCH_BASIC] += 1.0 * efficiency

        # 应用科研：每座活跃的实验室每天产出2点（受工人饱和度、耐久度、区域效率影响）
        labs = self.entities.get_buildings_by_type("laboratory")
        for lab in labs:
            durability_ratio = lab.durability / lab.max_durability if lab.max_durability > 0 else 0
            worker_ratio = lab.get_saturation()
            zone_eff = 1.0
            if lab.zone_id >= 0:
                zone = self.planet_zones.get_zone(lab.zone_id)
                if zone:
                    zone_eff = zone.get_work_efficiency()
            efficiency = durability_ratio * worker_ratio * zone_eff * dehydrate_mult
            output = 2.0 * efficiency * game_days_dt
            self.tech_tree.produce_research(RESEARCH_APPLIED, output)
            frame_output[RESEARCH_APPLIED] += 2.0 * efficiency

        # 理论科研：每座活跃的科学院每天产出1点（受工人饱和度、耐久度、区域效率影响）
        academies = self.entities.get_buildings_by_type("academy")
        for academy in academies:
            durability_ratio = academy.durability / academy.max_durability if academy.max_durability > 0 else 0
            worker_ratio = academy.get_saturation()
            zone_eff = 1.0
            if academy.zone_id >= 0:
                zone = self.planet_zones.get_zone(academy.zone_id)
                if zone:
                    zone_eff = zone.get_work_efficiency()
            efficiency = durability_ratio * worker_ratio * zone_eff * dehydrate_mult
            output = 1.0 * efficiency * game_days_dt
            self.tech_tree.produce_research(RESEARCH_THEORETICAL, output)
            frame_output[RESEARCH_THEORETICAL] += 1.0 * efficiency

        # 更新产出速率（指数移动平均，平滑显示）
        alpha = 0.05
        for rtype in self.research_output_rate:
            self.research_output_rate[rtype] = (
                alpha * frame_output[rtype]
                + (1 - alpha) * self.research_output_rate[rtype]
            )

        # 检查是否有研究刚完成并触发特殊效果
        if not self.tech_tree.researching_tech_id:
            auto_node = self.tech_tree.get_node("automation")
            if auto_node and auto_node.unlocked and self.entities.population.automation_multiplier < 1.3:
                self.entities.population.automation_multiplier = 1.3

    def _process_storage_damage(self, game_days_dt: float):
        """脱水状态下：库存人口和暴露人口的环境损耗

        库存设施根据所在区域环境计算损耗率：
        - 正常区域（温度-80~100, 辐射<10）：无损耗
        - 极端温度区域：每天损失 0.5%~5%
        - 高辐射区域：每天损失 0.5%~3%
        没有活跃库存设施时，库存人口全部死亡。

        暴露在环境中的活跃人口（未入库且非1%维持人员）额外受环境影响。
        """
        pop = self.entities.population

        # 检查是否还有活跃的库存设施
        active_storage_buildings = [
            b for b in self.entities.buildings
            if b.active and not b.destroyed and not b.under_construction and b.storage_capacity > 0
        ]

        if not active_storage_buildings and pop.stored_population > 0:
            # 没有库存设施，库存人口全部死亡
            pop.stored_population = 0
            return

        # 计算库存人口损耗
        total_stored = pop.stored_population
        if total_stored <= 0:
            return

        # 按库存设施的区域分配损耗
        total_capacity = sum(b.storage_capacity for b in active_storage_buildings)
        total_loss = 0.0

        for building in active_storage_buildings:
            if total_capacity <= 0:
                break
            # 按容量比例分配库存人口到该设施
            fraction = building.storage_capacity / total_capacity
            stored_here = total_stored * fraction

            if building.zone_id < 0:
                continue

            zone = self.planet_zones.get_zone(building.zone_id)
            if not zone:
                continue

            loss_rate = 0.0
            # 极端温度损耗
            if zone.temperature < -80:
                excess = (-80 - zone.temperature) / 100.0
                loss_rate += 0.005 + excess * 0.04  # 0.5% ~ 4.5%/天
            elif zone.temperature > 100:
                excess = (zone.temperature - 100) / 100.0
                loss_rate += 0.005 + excess * 0.04
            elif zone.temperature < -10:
                # 轻微寒冷也有少量损耗
                factor = (-10 - zone.temperature) / 70.0  # 0~1
                loss_rate += factor * 0.002  # 最多 0.2%/天
            elif zone.temperature > 60:
                factor = (zone.temperature - 60) / 40.0
                loss_rate += factor * 0.002

            # 高辐射损耗
            if zone.radiation > 5:
                excess = (zone.radiation - 5) / 10.0
                loss_rate += 0.003 + excess * 0.02  # 0.3% ~ 2.3%/天
            elif zone.radiation > 2:
                factor = (zone.radiation - 2) / 3.0
                loss_rate += factor * 0.001  # 最多 0.1%/天

            total_loss += stored_here * loss_rate * game_days_dt

        if total_loss > 0:
            pop.stored_population = max(0, int(pop.stored_population - total_loss))

        # 暴露在环境中的活跃人口额外损耗（不是1%维持人员的那部分）
        # 活跃人口 > 库存容量的人就是在暴露环境中
        exposed = max(0, pop.total - max(1, int((pop.total + pop.stored_population) * 0.01)))
        if exposed > 0:
            avg_env = self.planet_zones.get_average_environment()
            exposed_loss_rate = 0.0
            temp = avg_env.get("temperature", 20)
            rad = avg_env.get("radiation", 0)
            if temp < -80 or temp > 100:
                exposed_loss_rate = 0.1  # 极端环境10%/天
            elif temp < -10 or temp > 60:
                exposed_loss_rate = 0.02  # 恶劣环境2%/天
            if rad > 5:
                exposed_loss_rate += 0.05
            elif rad > 2:
                exposed_loss_rate += 0.01
            if exposed_loss_rate > 0:
                loss = int(exposed * exposed_loss_rate * game_days_dt)
                if loss > 0:
                    pop.total = max(1, pop.total - loss)

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
            "research_output_rate": dict(self.research_output_rate),
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
        """在游戏开始时校准 light_to_temp_scale 并将区域温度初始化

        校准思路：
        1. 先用默认 scale=500 计算一次全球平均温度
        2. 根据 target_temp=20°C 反推正确的 light_to_temp_scale
        3. 用校准后的系数重新初始化
        
        这样温度完全由光照驱动，而非人为偏移。
        """
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

        # 第一轮：用默认 scale 计算，获取原始平均温度和平均光照
        self.planet_zones.light_to_temp_scale = 500.0
        self.planet_zones.initialize_temperatures(stars_data, planet_position)

        # 计算全球加权平均光照和地形修正（用于校准 scale）
        from game.planet_zones import TERRAIN_THERMAL_MODIFIER
        total_weight = 0.0
        avg_raw_light = 0.0
        avg_terrain_mod = 0.0
        max_raw_light = 0.0
        for zone in self.planet_zones.zones:
            w = zone.area_weight
            terrain_mod = TERRAIN_THERMAL_MODIFIER.get(zone.terrain_type, 0.0)
            # 反算光照：temp = base + light * 500 + terrain_mod
            raw_light = (zone.temperature - self.planet_zones.base_temperature - terrain_mod) / 500.0
            avg_raw_light += raw_light * w
            avg_terrain_mod += terrain_mod * w
            total_weight += w
            if raw_light > max_raw_light:
                max_raw_light = raw_light

        if total_weight > 0:
            avg_raw_light /= total_weight
            avg_terrain_mod /= total_weight

        # 校准温度系数：target = base + avg_light * scale + avg_terrain_mod
        target_avg_temp = self._env_config.get("target_start_temp", 20.0)
        if avg_raw_light > 1e-6:
            self.planet_zones.light_to_temp_scale = (
                (target_avg_temp - self.planet_zones.base_temperature - avg_terrain_mod) / avg_raw_light
            )
        else:
            self.planet_zones.light_to_temp_scale = 500.0

        # 校准光照显示除数：使最亮区域约 target_peak_light
        target_peak = self._env_config.get("target_peak_light", 0.85)
        if max_raw_light > 1e-6:
            self.planet_zones.light_norm_divisor = max_raw_light / target_peak
        else:
            self.planet_zones.light_norm_divisor = 1.0

        # 第二轮：用校准后的系数重新初始化
        self.planet_zones.initialize_temperatures(stars_data, planet_position)