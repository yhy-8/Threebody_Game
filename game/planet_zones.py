"""行星区域系统 - 将行星球体划分为多个区域，模拟自转与逐区环境差异

新增特性：
  - 区域资源禀赋（铁/铜/稀有矿物密度、土地肥沃度、藻类密度）
  - 地形对资源禀赋的影响
  - 环境温度对工作效率的影响
"""
import math
import random
import numpy as np
from dataclasses import dataclass, field
from typing import List, Dict, Optional, Tuple


# ── 地形对资源禀赋的基础系数 ──────────────────────────────────────
#     铁    铜    稀有矿   肥沃度  藻类密度
TERRAIN_RESOURCE_TABLE: Dict[str, Dict[str, float]] = {
    "平原":  {"iron": 0.3, "copper": 0.2, "rare_mineral": 0.05, "fertility": 0.8, "algae": 0.4},
    "高原":  {"iron": 0.4, "copper": 0.3, "rare_mineral": 0.30, "fertility": 0.3, "algae": 0.1},
    "山地":  {"iron": 0.9, "copper": 0.5, "rare_mineral": 0.20, "fertility": 0.1, "algae": 0.0},
    "峡谷":  {"iron": 0.5, "copper": 0.8, "rare_mineral": 0.15, "fertility": 0.2, "algae": 0.3},
    "盆地":  {"iron": 0.2, "copper": 0.2, "rare_mineral": 0.05, "fertility": 0.9, "algae": 0.8},
    "丘陵":  {"iron": 0.6, "copper": 0.4, "rare_mineral": 0.10, "fertility": 0.5, "algae": 0.2},
}


def _calc_work_efficiency(temperature: float) -> float:
    """根据区域温度计算工作效率

    -10°~40° → 100%
    偏离此范围效率下降
    <-80° 或 >100° → 0%（无法工作）
    """
    if -10 <= temperature <= 40:
        return 1.0
    elif temperature < -80 or temperature > 100:
        return 0.0
    elif temperature < -10:
        # -80 → 0%, -10 → 100%
        return max(0.0, (temperature + 80) / 70.0)
    else:
        # 40 → 100%, 100 → 0%
        return max(0.0, (100 - temperature) / 60.0)


@dataclass
class PlanetZone:
    """行星上的一个区域"""
    zone_id: int
    lat_index: int           # 纬度索引 (0=南极, 5=北极)
    lon_index: int           # 经度索引 (0-11)
    lat_center: float        # 纬度中心 (度, -90 to 90)
    lon_center: float        # 经度中心 (度, 0 to 360)
    lat_range: Tuple[float, float]   # 纬度范围
    lon_range: Tuple[float, float]   # 经度范围
    terrain_type: str = "平原"       # 地形类型

    # 环境数据（每帧更新）
    temperature: float = -273.15
    radiation: float = 0.0
    light_intensity: float = 0.0

    # 资源禀赋（初始化时随机生成，受地形影响）
    resource_deposits: Dict[str, float] = field(default_factory=dict)
    fertility: float = 0.5           # 土地肥沃度（影响农业产出）
    algae_density: float = 0.3       # 藻类密度（影响藻类采集）

    # 建筑列表（存储建筑对象的引用ID）
    building_ids: List[int] = field(default_factory=list)

    # 区域面积权重（极地区域面积小于赤道区域）
    area_weight: float = 1.0

    def get_work_efficiency(self) -> float:
        """获取当前区域的工作效率（温度影响）"""
        return _calc_work_efficiency(self.temperature)


class PlanetZoneManager:
    """行星区域管理器

    将行星球体按照经纬网格划分为多个区域。
    每个区域有独立的法线方向，结合自转和恒星位置，
    实时计算该区域接收到的辐射、热量和光照。

    物理模型：
    - 区域法线 = sphere_normal(lat, lon + rotation_angle)
    - 恒星方向 = normalize(star_pos - planet_pos)
    - 区域光照 = max(0, dot(normal, star_dir)) * luminosity / dist²
    - 辐射使用 dist^2.5 衰减
    - 温度 = -273.15 + sum(各恒星贡献)
    """

    LATITUDE_DIVISIONS = 6     # 纬度分6带 (-90~-60, -60~-30, ..., 60~90)
    LONGITUDE_DIVISIONS = 12   # 经度分12带 (每30°一带)
    TOTAL_ZONES = LATITUDE_DIVISIONS * LONGITUDE_DIVISIONS  # 72

    # 地形类型列表（随机分配）
    TERRAIN_TYPES = ["平原", "高原", "山地", "峡谷", "盆地", "丘陵"]

    def __init__(self):
        self.zones: List[PlanetZone] = []
        self.rotation_angle: float = 0.0      # 当前自转角度 (度)
        self.rotation_speed: float = 15.0      # 自转速度 (°/游戏天)

        # 热惯性：区域温度不会瞬变，而是逐渐趋近目标温度
        self.thermal_inertia: float = 0.1      # 温度变化速率因子

        # 宜居基准偏移：校准使恒纪元开局全球平均~20°C
        self.habitable_offset: float = 0.0

        self._init_zones()

    def _init_zones(self):
        """初始化所有区域"""
        self.zones = []

        lat_step = 180.0 / self.LATITUDE_DIVISIONS   # 30°
        lon_step = 360.0 / self.LONGITUDE_DIVISIONS   # 30°

        zone_id = 0
        for lat_i in range(self.LATITUDE_DIVISIONS):
            lat_bottom = -90.0 + lat_i * lat_step
            lat_top = lat_bottom + lat_step
            lat_center = (lat_bottom + lat_top) / 2.0

            # 面积权重：依赖纬度的余弦（赤道=1，极地接近0）
            area_weight = math.cos(math.radians(lat_center))

            for lon_i in range(self.LONGITUDE_DIVISIONS):
                lon_left = lon_i * lon_step
                lon_right = lon_left + lon_step
                lon_center = (lon_left + lon_right) / 2.0

                terrain = random.choice(self.TERRAIN_TYPES)

                # 根据地形生成资源禀赋（基础值 ± 30% 随机浮动）
                base = TERRAIN_RESOURCE_TABLE.get(terrain, TERRAIN_RESOURCE_TABLE["平原"])
                resource_deposits = {}
                for mineral in ["iron", "copper", "rare_mineral"]:
                    base_val = base.get(mineral, 0.0)
                    jitter = base_val * random.uniform(-0.3, 0.3)
                    resource_deposits[mineral] = max(0.0, base_val + jitter)

                fertility = max(0.0, base.get("fertility", 0.5) + base.get("fertility", 0.5) * random.uniform(-0.3, 0.3))
                algae_dens = max(0.0, base.get("algae", 0.3) + base.get("algae", 0.3) * random.uniform(-0.3, 0.3))

                zone = PlanetZone(
                    zone_id=zone_id,
                    lat_index=lat_i,
                    lon_index=lon_i,
                    lat_center=lat_center,
                    lon_center=lon_center,
                    lat_range=(lat_bottom, lat_top),
                    lon_range=(lon_left, lon_right),
                    terrain_type=terrain,
                    area_weight=max(0.1, area_weight),
                    resource_deposits=resource_deposits,
                    fertility=fertility,
                    algae_density=algae_dens,
                )
                self.zones.append(zone)
                zone_id += 1

    def _get_zone_normal(self, zone: PlanetZone) -> np.ndarray:
        """计算区域法线方向（考虑自转角度）

        将球面坐标转换为3D笛卡尔坐标系的法线方向。
        自转体现为经度偏移。
        """
        lat_rad = math.radians(zone.lat_center)
        # 经度加上自转角度
        lon_rad = math.radians(zone.lon_center + self.rotation_angle)

        # 球面坐标 -> 笛卡尔坐标（右手系）
        nx = math.cos(lat_rad) * math.cos(lon_rad)
        ny = math.sin(lat_rad)
        nz = math.cos(lat_rad) * math.sin(lon_rad)

        return np.array([nx, ny, nz])

    def update(self, dt: float, time_scale: float, stars_data: list, planet_position: np.ndarray):
        """更新自转角度并重新计算每个区域的环境数据

        Args:
            dt: 帧间隔（秒）
            time_scale: 游戏时间倍率
            stars_data: 恒星列表 [{"position": ndarray, "mass": float, "is_planet": bool}, ...]
            planet_position: 行星当前位置 (ndarray)
        """
        # 更新自转角度
        game_days_elapsed = dt * time_scale
        self.rotation_angle += self.rotation_speed * game_days_elapsed
        self.rotation_angle %= 360.0

        # 收集所有恒星数据（排除行星自身）
        active_stars = []
        for s in stars_data:
            if s.get("is_planet", False):
                continue
            star_pos = s["position"] if isinstance(s["position"], np.ndarray) else np.array(s["position"])
            direction = star_pos - planet_position
            dist = np.linalg.norm(direction)
            if dist < 1e-6:
                continue
            star_dir = direction / dist
            active_stars.append({
                "direction": star_dir,
                "distance": dist,
                "mass": s.get("mass", 1000.0),
            })

        # 计算每个区域的环境数据
        self._compute_zone_environments(active_stars, game_days_elapsed)

    def initialize_temperatures(self, stars_data: list, planet_position: np.ndarray):
        """在游戏开始时将所有区域温度初始化为目标温度（跳过热惯性过渡）

        Args:
            stars_data: 恒星列表
            planet_position: 行星当前位置
        """
        active_stars = []
        for s in stars_data:
            if s.get("is_planet", False):
                continue
            star_pos = s["position"] if isinstance(s["position"], np.ndarray) else np.array(s["position"])
            direction = star_pos - planet_position
            dist = np.linalg.norm(direction)
            if dist < 1e-6:
                continue
            star_dir = direction / dist
            active_stars.append({
                "direction": star_dir,
                "distance": dist,
                "mass": s.get("mass", 1000.0),
            })

        for zone in self.zones:
            normal = self._get_zone_normal(zone)
            target_temp_contribution = 0.0
            target_radiation = 0.0
            target_light = 0.0

            for star in active_stars:
                cos_angle = np.dot(normal, star["direction"])
                scatter_factor = 0.05 if cos_angle <= 0 else cos_angle
                dist = star["distance"]
                mass = star["mass"]

                intensity = mass * 10.0 / (dist * dist + 100.0) * scatter_factor
                target_light += intensity
                safe_dist = max(5.0, dist)
                rad = mass * 200.0 / (safe_dist ** 2.5) * scatter_factor
                target_radiation += rad
                target_temp_contribution += intensity * 500.0

            zone.temperature = -273.15 + target_temp_contribution + self.habitable_offset
            zone.radiation = target_radiation
            zone.light_intensity = min(1.0, target_light / 8.0)

    def _compute_zone_environments(self, active_stars: list, game_days_elapsed: float):
        """计算每个区域的环境数据（抽取为独立方法以便复用）"""
        for zone in self.zones:
            normal = self._get_zone_normal(zone)

            target_temp_contribution = 0.0
            target_radiation = 0.0
            target_light = 0.0

            for star in active_stars:
                cos_angle = np.dot(normal, star["direction"])

                if cos_angle <= 0:
                    scatter_factor = 0.05
                else:
                    scatter_factor = cos_angle

                dist = star["distance"]
                mass = star["mass"]

                intensity = mass * 10.0 / (dist * dist + 100.0) * scatter_factor
                target_light += intensity

                safe_dist = max(5.0, dist)
                rad = mass * 200.0 / (safe_dist ** 2.5) * scatter_factor
                target_radiation += rad

                target_temp_contribution += intensity * 500.0

            # 目标温度
            target_temp = -273.15 + target_temp_contribution + self.habitable_offset

            # 热惯性：缓慢趋近目标温度
            inertia_factor = min(1.0, self.thermal_inertia * abs(game_days_elapsed))
            zone.temperature += (target_temp - zone.temperature) * inertia_factor
            zone.radiation = target_radiation
            zone.light_intensity = min(1.0, target_light / 8.0)

    def get_zone(self, zone_id: int) -> Optional[PlanetZone]:
        """获取指定区域"""
        if 0 <= zone_id < len(self.zones):
            return self.zones[zone_id]
        return None

    def get_zone_at(self, lat: float, lon: float) -> Optional[PlanetZone]:
        """根据经纬度查找区域"""
        for zone in self.zones:
            if (zone.lat_range[0] <= lat < zone.lat_range[1] and
                    zone.lon_range[0] <= lon < zone.lon_range[1]):
                return zone
        return None

    def get_average_environment(self) -> dict:
        """计算全球加权平均环境数据（用于主界面显示）"""
        total_weight = 0.0
        avg_temp = 0.0
        avg_rad = 0.0
        avg_light = 0.0

        for zone in self.zones:
            w = zone.area_weight
            avg_temp += zone.temperature * w
            avg_rad += zone.radiation * w
            avg_light += zone.light_intensity * w
            total_weight += w

        if total_weight > 0:
            avg_temp /= total_weight
            avg_rad /= total_weight
            avg_light /= total_weight

        return {
            "temperature": avg_temp,
            "radiation": avg_rad,
            "light_intensity": avg_light,
        }

    def get_zone_environment(self, zone_id: int) -> dict:
        """获取指定区域的详细环境数据"""
        zone = self.get_zone(zone_id)
        if not zone:
            return {}
        return {
            "zone_id": zone.zone_id,
            "lat_center": zone.lat_center,
            "lon_center": zone.lon_center,
            "lat_range": zone.lat_range,
            "lon_range": zone.lon_range,
            "terrain_type": zone.terrain_type,
            "temperature": zone.temperature,
            "radiation": zone.radiation,
            "light_intensity": zone.light_intensity,
            "building_count": len(zone.building_ids),
            "area_weight": zone.area_weight,
            "resource_deposits": dict(zone.resource_deposits),
            "fertility": zone.fertility,
            "algae_density": zone.algae_density,
            "work_efficiency": zone.get_work_efficiency(),
        }

    def get_illuminated_zones(self) -> List[int]:
        """获取当前受光面的区域ID列表"""
        return [z.zone_id for z in self.zones if z.light_intensity > 0.05]

    def get_all_zones_summary(self) -> List[dict]:
        """获取所有区域的简要数据（用于2D地图渲染）"""
        return [
            {
                "id": z.zone_id,
                "lat_i": z.lat_index,
                "lon_i": z.lon_index,
                "temp": z.temperature,
                "rad": z.radiation,
                "light": z.light_intensity,
                "terrain": z.terrain_type,
                "buildings": len(z.building_ids),
                "fertility": z.fertility,
                "algae": z.algae_density,
                "deposits": dict(z.resource_deposits),
            }
            for z in self.zones
        ]

    def add_building_to_zone(self, zone_id: int, building_id: int) -> bool:
        """向指定区域添加建筑"""
        zone = self.get_zone(zone_id)
        if zone:
            zone.building_ids.append(building_id)
            return True
        return False

    def remove_building_from_zone(self, zone_id: int, building_id: int):
        """从指定区域移除建筑"""
        zone = self.get_zone(zone_id)
        if zone and building_id in zone.building_ids:
            zone.building_ids.remove(building_id)

    def get_state(self) -> dict:
        """序列化状态（用于保存）"""
        return {
            "rotation_angle": self.rotation_angle,
            "zones": [
                {
                    "zone_id": z.zone_id,
                    "terrain_type": z.terrain_type,
                    "building_ids": z.building_ids.copy(),
                    "temperature": z.temperature,
                    "resource_deposits": dict(z.resource_deposits),
                    "fertility": z.fertility,
                    "algae_density": z.algae_density,
                }
                for z in self.zones
            ]
        }

    def load_state(self, data: dict):
        """从数据恢复状态"""
        self.rotation_angle = data.get("rotation_angle", 0.0)
        zones_data = data.get("zones", [])
        for zd in zones_data:
            zone = self.get_zone(zd.get("zone_id", -1))
            if zone:
                zone.terrain_type = zd.get("terrain_type", zone.terrain_type)
                zone.building_ids = zd.get("building_ids", [])
                zone.temperature = zd.get("temperature", -273.15)
                # 恢复资源禀赋（如果存档有就用存档的，否则保持初始化随机值）
                if "resource_deposits" in zd:
                    zone.resource_deposits = zd["resource_deposits"]
                if "fertility" in zd:
                    zone.fertility = zd["fertility"]
                if "algae_density" in zd:
                    zone.algae_density = zd["algae_density"]
