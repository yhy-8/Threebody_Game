"""三体环境模拟 - 三体运动计算与环境参数输出"""
import numpy as np
from dataclasses import dataclass, field
from typing import List, Tuple


@dataclass
class Star:
    """恒星或行星"""
    mass: float
    position: np.ndarray = field(default_factory=lambda: np.zeros(3))
    velocity: np.ndarray = field(default_factory=lambda: np.zeros(3))
    color: Tuple[int, int, int] = (255, 255, 255)
    radius: float = 20.0
    is_planet: bool = False  # 是否是行星
    trail: List[np.ndarray] = field(default_factory=list)  # 轨迹历史位置


class ThreeBodySimulation:
    """三体运动模拟器"""

    G = 1.0  # 引力常数（简化）
    TRAIL_LENGTH = 200  # 轨迹保留的点数，加长以使恒星轨迹更明显

    def __init__(self):
        self.stars: List[Star] = []
        self.time_scale = 1.0
        self._initialize_stars()

    def _initialize_stars(self):
        """初始化三颗恒星和一颗行星"""
        # 采用层级稳定配置
        
        # 恒星1：橙色主星（类似太阳）
        star1 = Star(
            mass=1000.0,
            position=np.array([0.0, 0.0, 0.0]),
            velocity=np.array([0.0, 0.0, -0.3]),
            color=(255, 200, 100),
            radius=30.0,  # 缩小半径以匹配更大距离
            is_planet=False
        )

        # 恒星2：蓝色
        star2 = Star(
            mass=800.0,
            position=np.array([500.0, 0.0, 100.0]),
            velocity=np.array([-0.5, 0.0, 0.8]),
            color=(100, 200, 255),
            radius=25.0,
            is_planet=False
        )

        # 恒星3：红色
        star3 = Star(
            mass=600.0,
            position=np.array([-400.0, 0.0, -300.0]),
            velocity=np.array([0.6, 0.0, 0.5]),
            color=(255, 100, 100),
            radius=20.0,
            is_planet=False
        )

        # 行星：蓝色小型天体（类似地球）
        # 行星紧密绕恒星1运行
        planet = Star(
            mass=1.0,
            position=np.array([80.0, 0.0, 0.0]), # 放置在恒星1外侧
            velocity=np.array([0.0, 0.0, 3.5]),  # 给足初速度以形成轨道
            color=(100, 150, 255),
            radius=3.0,
            is_planet=True
        )

        self.stars = [star1, star2, star3, planet]

    def compute_forces(self) -> List[np.ndarray]:
        """计算每颗恒星受到的引力"""
        forces = [np.zeros(3) for _ in self.stars]

        for i, star_i in enumerate(self.stars):
            for j, star_j in enumerate(self.stars):
                if i != j:
                    r = star_j.position - star_i.position
                    dist = np.linalg.norm(r)
                    if dist > 1e-6:
                        force = self.G * star_i.mass * star_j.mass * r / (dist ** 3)
                        forces[i] += force

        return forces

    def update(self, dt: float):
        """更新三体运动（使用半隐式欧拉法）"""
        dt = dt * self.time_scale
        forces = self.compute_forces()

        # 更新速度和位置
        for star, force in zip(self.stars, forces):
            # 记录当前位置到轨迹
            star.trail.append(star.position.copy())
            # 限制轨迹长度
            if len(star.trail) > self.TRAIL_LENGTH:
                star.trail.pop(0)

            acceleration = force / star.mass
            star.velocity += acceleration * dt
            star.position += star.velocity * dt

    def get_environment_params(self) -> dict:
        """获取环境参数（光照、热量等）"""
        # 寻找行星
        planet = None
        for star in self.stars:
            if star.is_planet:
                planet = star
                break

        if not planet:
            return {
                "light_intensity": 0.0,
                "heat_level": 0.0,
                "stability": 0.0,
            }

        # 计算行星到各恒星的距离和总光照/热量
        total_intensity = 0.0
        min_dist = float('inf')

        for star in self.stars:
            if star is planet:
                continue
            
            # 星球间距离
            dist = np.linalg.norm(star.position - planet.position)
            min_dist = min(min_dist, dist)
            
            # 光照和热量受距离平方反比和恒星质量影响
            # 基础光照计算：质量大的恒星光照强，距离近光照强
            # 为了游戏性，添加一些常数调整
            intensity = star.mass * 10 / (dist * dist + 100)
            total_intensity += intensity

        # 计算稳定性：基于行星受到的合力差异（或速度变化）
        # 这里用一种简单方式：行星离恒星太近或太远都不稳定，
        # 合理距离内（如受到的引力比较平衡时）比较稳定。
        stability = self._compute_stability(planet)

        return {
            "light_intensity": min(1.0, total_intensity / 8.0),
            "heat_level": min(1.0, total_intensity / 6.0),
            "stability": stability,
        }

    def _compute_stability(self, planet: Star) -> float:
        """计算星系稳定性（基于行星受到的加速度）"""
        total_force = np.zeros(3)
        for star in self.stars:
            if star is planet:
                continue
            r = star.position - planet.position
            dist = np.linalg.norm(r)
            if dist > 1e-6:
                force = self.G * planet.mass * star.mass * r / (dist ** 3)
                total_force += force
                
        # 行星加速度
        accel = np.linalg.norm(total_force) / planet.mass
        
        # 加速度太大（靠近恒星或被剧烈拉扯）导致不稳定
        # 0.1 是一个设定的"正常"加速度，超过这个值稳定性就快速下降
        return 1.0 / (1.0 + accel / 0.1)