"""3D场景渲染"""
import pygame
import random
import math
import numpy as np
from typing import List, Tuple, Optional
from .camera import Camera


class StarField:
    """星空粒子系统 - 3D世界坐标版本"""

    def __init__(self, count: int = 500, range_size: float = 2000):
        self.count = count
        self.range_size = range_size  # 星空分布范围
        self.stars = self._generate_stars()

    def _generate_stars(self) -> List[Tuple]:
        """生成3D世界坐标的星星"""
        return [
            (
                random.uniform(-self.range_size, self.range_size),
                random.uniform(-self.range_size, self.range_size),
                random.uniform(-self.range_size, self.range_size),
                random.uniform(0.5, 2.5),  # size
                random.randint(100, 255)   # brightness
            )
            for _ in range(self.count)
        ]

    def render(self, screen: pygame.Surface, camera):
        """渲染星空 - 根据摄像机位置产生视差"""
        screen_size = screen.get_size()

        for x, y, z, size, base_bright in self.stars:
            # 将星星从世界坐标转换到屏幕坐标
            screen_pos = camera.world_to_screen(x, y, z, screen_size)

            if screen_pos is None:
                continue

            sx, sy = screen_pos

            # 检查是否在屏幕范围内
            if not (-50 <= sx <= screen_size[0] + 50 and -50 <= sy <= screen_size[1] + 50):
                continue

            # 轻微闪烁效果
            bright = int(base_bright * (0.85 + 0.15 * random.random()))
            color = (bright, bright, bright)
            draw_size = max(1, int(size))

            pygame.draw.circle(screen, color, (sx, sy), draw_size)


class SceneRenderer:
    """3D场景渲染器"""

    def __init__(self, screen: pygame.Surface, camera: Camera):
        self.screen = screen
        self.camera = camera
        self.star_field = StarField(count=300)

    def clear(self, color: Tuple[int, int, int] = (10, 10, 20)):
        """清空屏幕"""
        self.screen.fill(color)

    def render(self, game_state: dict, zone_data: Optional[dict] = None):
        """渲染游戏场景

        Args:
            game_state: 游戏状态字典
            zone_data: 行星区域数据（包含 rotation_angle 和 zones_summary）
        """
        # 1. 绘制星空背景（传入camera实现视差）
        self.star_field.render(self.screen, self.camera)

        # 2. 绘制恒星和行星
        for star_data in game_state.get("environment", {}).get("stars", []):
            self._draw_star(star_data, zone_data)

        # 3. 绘制轨道（可选）
        self._draw_orbit_hint()

    def _draw_star(self, star_data: dict, zone_data: Optional[dict] = None):
        """绘制恒星或行星（使用球体感渐变，行星显示区域网格）"""
        pos = star_data["position"]
        color = star_data["color"]
        radius = star_data["radius"]
        is_planet = star_data.get("is_planet", False)
        trail = star_data.get("trail", [])

        # 先获取屏幕坐标
        screen_pos = self.camera.world_to_screen(
            pos[0], pos[1], pos[2],
            self.screen.get_size()
        )

        # 把绘制轨迹的逻辑移到这里，在确定这颗星不是在视野后面完全不可见的情况下绘制
        # 即使星体因为超出屏幕返回了None，轨迹还是应该绘制的，因为轨迹可能有部分在屏幕内
        # 原本的代码这里如果是None就直接return了，可能会导致一些轨迹闪烁
        
        # 绘制渐变实体
        if screen_pos is not None:
            sx, sy = screen_pos

            scale = self.camera.get_scale(pos[0], pos[1], pos[2])
            screen_radius = max(1, int(radius * scale))

            if screen_radius < 2:
                # 太小只画实心圆
                pygame.draw.circle(self.screen, color, (sx, sy), screen_radius)
            else:
                # 行星的渲染：蓝色渐变到暗色（有明暗面）
                if is_planet:
                    # 计算行星相对于恒星的光照方向（简化：以原点方向为光照）
                    to_light = np.array(pos) / (np.linalg.norm(pos) + 1e-6)
                    # 简化：根据位置计算明暗
                    light_factor = 0.5 + 0.5 * (pos[2] / (abs(pos[0]) + abs(pos[2]) + 1))

                    for r in range(screen_radius, 0, -2):
                        factor = 1 - (r / screen_radius) ** 2
                        # 行星暗面更暗
                        bright = tuple(int(c * (0.2 + 0.8 * factor * light_factor)) for c in color)
                        bright = tuple(min(255, max(0, b)) for b in bright)
                        pygame.draw.circle(self.screen, bright, (sx, sy), r)

                    # 绘制区域网格线（经纬线）
                    if screen_radius >= 8:
                        rotation_angle = 0.0
                        if zone_data:
                            rotation_angle = zone_data.get("rotation_angle", 0.0)
                        self._draw_planet_grid(
                            screen_pos, screen_radius, pos, rotation_angle
                        )
                else:
                    # 恒星：发光效果（中心亮，边缘暗）
                    for r in range(screen_radius, 0, -2):
                        factor = 1 - (r / screen_radius) ** 2
                        bright = tuple(min(255, int(c * (0.3 + 0.7 * factor))) for c in color)
                        pygame.draw.circle(self.screen, bright, (sx, sy), r)
                        
        # **最后**绘制轨迹，确保恒星巨大半径不会遮挡其本身的轨迹
        if trail and len(trail) > 1:
            self._draw_trail(trail, color, is_planet)

    def _draw_trail(self, trail: list, base_color: Tuple[int, int, int], is_planet: bool = False):
        """绘制渐变消失的轨迹（带发光效果）"""
        screen_size = self.screen.get_size()
        points = []

        # 将3D轨迹点转换为2D屏幕坐标
        for pos in trail:
            screen_pos = self.camera.world_to_screen(pos[0], pos[1], pos[2], screen_size)
            if screen_pos:
                points.append(screen_pos)

        if len(points) < 2:
            return

        total = len(points)
        
        # 根据是否是行星调整粗细和发光强度
        glow_max_width = 4 if is_planet else 12
        main_max_width = 2 if is_planet else 6
        glow_alpha_factor = 0.15 if is_planet else 0.35
        main_alpha_min = 0.3 if is_planet else 0.5
        main_alpha_range = 0.7 if is_planet else 0.5

        # 第一遍：绘制发光底层（更宽、更暗的线条模拟光晕）
        for i in range(len(points) - 1):
            t = i / total  # 0(旧) -> 1(新)
            # 光晕颜色：基础色 * 低亮度
            glow_color = tuple(max(0, min(255, int(c * (0.05 + glow_alpha_factor * t)))) for c in base_color)
            p1, p2 = points[i], points[i + 1]
            glow_width = max(3, int(glow_max_width * t))
            pygame.draw.line(self.screen, glow_color, p1, p2, glow_width)

        # 第二遍：绘制主轨迹线（更亮、更窄）
        for i in range(len(points) - 1):
            t = i / total  # 0(旧) -> 1(新)
            # 主线颜色
            faded_color = tuple(max(0, min(255, int(c * (main_alpha_min + main_alpha_range * t)))) for c in base_color)
            p1, p2 = points[i], points[i + 1]
            width = max(1, int(main_max_width * t))
            pygame.draw.line(self.screen, faded_color, p1, p2, width)

    def _draw_orbit_hint(self):
        """绘制轨道提示（简单的连线）"""
        stars = []
        for star_data in [s for s in self.camera._rotate_y.__self__.stars] if hasattr(self.camera, 'stars') else []:
            # 这里简化处理，实际应该从game_state获取
            pass

    def draw_line_3d(
        self,
        x1: float, y1: float, z1: float,
        x2: float, y2: float, z2: float,
        color: Tuple[int, int, int],
        width: int = 1
    ):
        """绘制3D线"""
        screen_size = self.screen.get_size()
        p1 = self.camera.world_to_screen(x1, y1, z1, screen_size)
        p2 = self.camera.world_to_screen(x2, y2, z2, screen_size)

        if p1 and p2:
            pygame.draw.line(self.screen, color, p1, p2, width)

    def draw_point_3d(
        self,
        x: float, y: float, z: float,
        color: Tuple[int, int, int],
        size: int = 3
    ):
        """绘制3D点"""
        screen_size = self.screen.get_size()
        pos = self.camera.world_to_screen(x, y, z, screen_size)

        if pos:
            pygame.draw.circle(self.screen, color, pos, size)

    def render_game_over(self, screen: pygame.Surface):
        """渲染游戏结束画面"""
        screen_size = screen.get_size()

        # 红色半透明遮罩
        overlay = pygame.Surface(screen_size)
        overlay.set_alpha(128)
        overlay.fill((150, 0, 0))
        screen.blit(overlay, (0, 0))

        # 游戏结束文字
        font = pygame.font.Font(None, 72)
        text = font.render("游戏结束!", True, (255, 50, 50))
        text_rect = text.get_rect(center=(screen_size[0] // 2, screen_size[1] // 2 - 30))
        screen.blit(text, text_rect)

        # 提示文字
        font_small = pygame.font.Font(None, 36)
        hint = font_small.render("你已撞击星球", True, (255, 200, 200))
        hint_rect = hint.get_rect(center=(screen_size[0] // 2, screen_size[1] // 2 + 30))
        screen.blit(hint, hint_rect)

    def _draw_planet_grid(self, screen_center: Tuple[int, int],
                          screen_radius: int, world_pos: list,
                          rotation_angle: float = 0.0):
        """在行星球体上绘制经纬网格线

        使用投影将球面上的经纬线映射到2D屏幕空间，
        实现行星区域的可视化和自转效果。

        Args:
            screen_center: 行星屏幕中心坐标
            screen_radius: 行星屏幕半径
            world_pos: 行星世界坐标
            rotation_angle: 当前自转角度(度)
        """
        if screen_radius < 6:
            return

        cx, cy = screen_center
        R = screen_radius
        rot_rad = math.radians(rotation_angle)

        line_color = (60, 80, 120)
        thin_color = (40, 55, 85)

        # 纬线（6条分割线 = 7个纬度带边界，去掉两极）
        lat_steps = 6
        for i in range(1, lat_steps):
            lat = -90 + i * (180.0 / lat_steps)
            lat_rad = math.radians(lat)

            # 纬线是一个水平椭圆
            # y 偏移 = R * sin(lat)
            # 椭圆宽度 = R * cos(lat)
            y_offset = -R * math.sin(lat_rad)  # 屏幕Y轴正方向向下
            half_width = R * math.cos(lat_rad)

            if half_width < 2:
                continue

            # 绘制纬线的可见部分（一个椭圆弧）
            rect = pygame.Rect(
                int(cx - half_width),
                int(cy + y_offset - half_width * 0.1),
                int(half_width * 2),
                max(2, int(half_width * 0.2))
            )
            color = line_color if i == lat_steps // 2 else thin_color  # 赤道加亮
            try:
                pygame.draw.ellipse(self.screen, color, rect, 1)
            except (ValueError, pygame.error):
                pass

        # 经线（12条分割线，每30度一条）
        lon_steps = 12
        segments = 24  # 每条经线的分段数
        for j in range(lon_steps):
            lon = j * (360.0 / lon_steps) + rotation_angle
            lon_rad = math.radians(lon)

            points = []
            for k in range(segments + 1):
                lat = -90 + k * (180.0 / segments)
                lat_rad = math.radians(lat)

                # 球面坐标 -> 简化的2D投影
                # x方向 = cos(lat) * sin(lon)
                # y方向 = sin(lat)
                # z方向 = cos(lat) * cos(lon)（深度，用于判断可见性）
                x3d = math.cos(lat_rad) * math.sin(lon_rad)
                y3d = math.sin(lat_rad)
                z3d = math.cos(lat_rad) * math.cos(lon_rad)

                # 只绘制面向观察者的部分（z > 0 表示面朝相机，简化处理）
                if z3d < -0.05:
                    if points and len(points) > 1:
                        try:
                            pygame.draw.lines(self.screen, thin_color, False, points, 1)
                        except (ValueError, pygame.error):
                            pass
                    points = []
                    continue

                sx = int(cx + x3d * R)
                sy = int(cy - y3d * R)  # 屏幕Y轴向下
                points.append((sx, sy))

            if len(points) > 1:
                color = line_color if j % 3 == 0 else thin_color  # 每90度加亮
                try:
                    pygame.draw.lines(self.screen, color, False, points, 1)
                except (ValueError, pygame.error):
                    pass