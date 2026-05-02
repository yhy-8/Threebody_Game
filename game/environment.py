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
        import random
        import math
        """初始化三颗恒星和一颗行星 (采用随机层级稳定配置)

        恒纪元开局：恒星参数范围收紧，确保初始温度宜居（全球平均~20°C）
        """

        # 内层双星：质量范围收紧
        m1 = random.uniform(900.0, 1100.0)
        m2 = random.uniform(700.0, 900.0)

        # 双星间距范围收紧
        binary_dist = random.uniform(180.0, 220.0)

        # 估算相对速度 v = sqrt(G(m1+m2)/r)
        v_rel = math.sqrt(self.G * (m1 + m2) / binary_dist)

        # 根据质量分配距离和速度
        r1 = binary_dist * (m2 / (m1 + m2))
        r2 = binary_dist * (m1 / (m1 + m2))

        v1 = v_rel * (m2 / (m1 + m2))
        v2 = v_rel * (m1 / (m1 + m2))

        # 随机给双星轨道一个初始旋转相位
        angle = random.uniform(0, 2 * math.pi)

        star1 = Star(
            mass=m1,
            position=np.array([r1 * math.cos(angle), 0.0, r1 * math.sin(angle)]),
            velocity=np.array([-v1 * math.sin(angle), 0.0, v1 * math.cos(angle)]),
            color=(255, random.randint(180, 220), 100),
            radius=random.uniform(25.0, 35.0),
            is_planet=False
        )

        star2 = Star(
            mass=m2,
            position=np.array([-r2 * math.cos(angle), 0.0, -r2 * math.sin(angle)]),
            velocity=np.array([v2 * math.sin(angle), 0.0, -v2 * math.cos(angle)]),
            color=(100, random.randint(180, 220), 255),
            radius=random.uniform(20.0, 30.0),
            is_planet=False
        )

        # 外层第三恒星，距离范围收紧
        m3 = random.uniform(500.0, 700.0)
        outer_dist = random.uniform(650.0, 800.0)
        v_outer = math.sqrt(self.G * (m1 + m2 + m3) / outer_dist)
        outer_angle = random.uniform(0, 2 * math.pi)

        star3 = Star(
            mass=m3,
            position=np.array([outer_dist * math.cos(outer_angle), random.uniform(-30, 30), outer_dist * math.sin(outer_angle)]),
            velocity=np.array([-v_outer * math.sin(outer_angle), random.uniform(-0.05, 0.05), v_outer * math.cos(outer_angle)]),
            color=(255, random.randint(80, 120), random.randint(80, 120)),
            radius=random.uniform(18.0, 25.0),
            is_planet=False
        )

        # 行星，围绕内侧双星运转，距离范围收紧以确保宜居温度
        planet_dist = outer_dist * random.uniform(0.4, 0.5)
        p_angle = random.uniform(0, 2 * math.pi)
        # 接近圆轨道，微小偏差保持长期稳定性
        v_planet = math.sqrt(self.G * (m1 + m2) / planet_dist) * random.uniform(0.9, 1.1)

        planet = Star(
            mass=1.0,
            position=np.array([planet_dist * math.cos(p_angle), 0.0, planet_dist * math.sin(p_angle)]),
            velocity=np.array([-v_planet * math.sin(p_angle), 0.0, v_planet * math.cos(p_angle)]),
            color=(100, 150, 255),
            radius=3.0,
            is_planet=True
        )

        self.stars = [star1, star2, star3, planet]

    def compute_forces_for_state(self, positions: List[np.ndarray]) -> List[np.ndarray]:
        """为给定位置列表计算每颗恒星受到的引力"""
        forces = [np.zeros(3) for _ in self.stars]
        for i in range(len(self.stars)):
            for j in range(len(self.stars)):
                if i != j:
                    r = positions[j] - positions[i]
                    dist = np.linalg.norm(r)
                    if dist > 1e-6:
                        force = self.G * self.stars[i].mass * self.stars[j].mass * r / (dist ** 3)
                        forces[i] += force
        return forces

    def update(self, dt: float):
        """更新三体运动（使用RK4方法 + 随机微扰）"""
        dt = dt * self.time_scale
        import random

        if dt <= 0:
            return

        positions = [star.position.copy() for star in self.stars]
        velocities = [star.velocity.copy() for star in self.stars]
        masses = [star.mass for star in self.stars]
        
        # RK4 Step 1
        forces1 = self.compute_forces_for_state(positions)
        a1 = [f / m for f, m in zip(forces1, masses)]
        
        # RK4 Step 2
        pos2 = [p + v * (dt / 2) for p, v in zip(positions, velocities)]
        v2_temp = [v + a * (dt / 2) for v, a in zip(velocities, a1)]
        forces2 = self.compute_forces_for_state(pos2)
        a2 = [f / m for f, m in zip(forces2, masses)]
        
        # RK4 Step 3
        pos3 = [p + v * (dt / 2) for p, v in zip(positions, v2_temp)]
        v3_temp = [v + a * (dt / 2) for v, a in zip(velocities, a2)]
        forces3 = self.compute_forces_for_state(pos3)
        a3 = [f / m for f, m in zip(forces3, masses)]
        
        # RK4 Step 4
        pos4 = [p + v * dt for p, v in zip(positions, v3_temp)]
        forces4 = self.compute_forces_for_state(pos4)
        a4 = [f / m for f, m in zip(forces4, masses)]
        
        # 综合更新与微小随机演化
        for i, star in enumerate(self.stars):
            # 记录当前位置到轨迹
            star.trail.append(star.position.copy())
            if len(star.trail) > self.TRAIL_LENGTH:
                star.trail.pop(0)
                
            # 计算加权平均的加速度和速度 (RK4 Integration)
            avg_a = (a1[i] + 2*a2[i] + 2*a3[i] + a4[i]) / 6.0
            avg_v = (velocities[i] + 2*v2_temp[i] + 2*v3_temp[i] + (velocities[i] + a3[i] * dt)) / 6.0
            
            # 微小随机扰动（量子涨落/宇宙背景微扰）
            # 即使相同的宏观初始坐标，随时间演变也会走向不同解
            perturbation_a = np.array([
                random.uniform(-1e-5, 1e-5),
                random.uniform(-1e-5, 1e-5),
                random.uniform(-1e-5, 1e-5)
            ])
            
            star.velocity += (avg_a + perturbation_a) * dt
            star.position += avg_v * dt

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
                "temperature": -273.15,
                "radiation": 0.0,
                "stability": 0.0,
            }

        # 计算行星到各恒星的距离和总光照/热量
        total_intensity = 0.0
        radiation = 0.0

        for star in self.stars:
            if star is planet:
                continue
            
            # 星球间距离
            dist = np.linalg.norm(star.position - planet.position)
            
            # 光照和热量受距离平方反比和恒星质量影响
            # 基础光照计算：质量大的恒星光照强，距离近光照强
            # 为了游戏性，添加一些常数调整
            intensity = star.mass * 10 / (dist * dist + 100)
            total_intensity += intensity
            
            # 辐射：极近距离急剧攀升
            safe_dist = max(5.0, dist)
            rad = star.mass * 200 / (safe_dist ** 2.5)
            radiation += rad

        # 计算稳定性：基于行星受到的合力差异（或速度变化）
        stability = self._compute_stability(planet)
        
        # 基础温度 -273.15℃，根据接收到的热量增加
        # 调整乘数使稳定纪元下全球平均约20°C
        temperature = -273.15 + (total_intensity * 7000.0)

        return {
            "light_intensity": min(1.0, total_intensity / 8.0),
            "heat_level": total_intensity / 6.0,
            "temperature": temperature,
            "radiation": radiation,
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