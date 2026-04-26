"""区域浏览界面 - 查看行星各区域的环境数据和建筑信息"""

import pygame
import math
from typing import Optional, Tuple

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font


class ZoneViewScreen(Screen):
    """行星区域浏览界面

    左侧：2D行星展开图（Mercator投影风格的 12×6 网格）
    右侧：选中区域的详细信息面板
    顶部：全球概览数据
    """

    # 显示模式
    MODE_TEMPERATURE = 0
    MODE_RADIATION = 1
    MODE_LIGHT = 2

    MODE_NAMES = {0: "温度", 1: "辐射", 2: "光照"}

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.selected_zone_id: int = -1
        self.display_mode = self.MODE_TEMPERATURE
        self.message = ""
        self.message_timer = 0.0

        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        btn_font_size = max(16, int(22 * scale))
        btn_h = max(32, int(40 * scale))

        self.back_button = MenuButton(
            int(20 * scale), int(20 * scale), max(100, int(120 * scale)), btn_h,
            "← 返回",
            callback=self.on_back,
            font_size=btn_font_size
        )

        # 显示模式切换按钮
        mode_x = int(width * 0.25)
        mode_w = max(80, int(100 * scale))
        self.mode_buttons = []
        for i, mode_name in self.MODE_NAMES.items():
            btn = MenuButton(
                mode_x + i * (mode_w + 10), int(20 * scale), mode_w, btn_h,
                mode_name,
                callback=lambda m=i: self.set_display_mode(m),
                font_size=max(14, int(18 * scale))
            )
            self.mode_buttons.append(btn)

        self.load_fonts()

    def set_display_mode(self, mode: int):
        """切换显示模式"""
        self.display_mode = mode

    def on_back(self):
        """返回主界面"""
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.selected_zone_id = -1
        self.setup_ui()

    def update(self, dt: float):
        """更新"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt
        self.back_button.update(dt)
        for btn in self.mode_buttons:
            btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        if self.back_button.handle_event(event):
            return True
        for btn in self.mode_buttons:
            if btn.handle_event(event):
                return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True
            elif event.key == pygame.K_TAB:
                self.display_mode = (self.display_mode + 1) % 3
                return True

        # 点击网格选择区域
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            zone_id = self._get_zone_at_mouse(event.pos)
            if zone_id >= 0:
                self.selected_zone_id = zone_id
                return True

        return False

    def _get_grid_area(self) -> Tuple[int, int, int, int]:
        """获取网格绘制区域"""
        width, height = self.screen.get_size()
        grid_x = int(width * 0.03)
        grid_y = int(height * 0.18)
        grid_w = int(width * 0.58)
        grid_h = int(height * 0.75)
        return grid_x, grid_y, grid_w, grid_h

    def _get_zone_at_mouse(self, pos: Tuple[int, int]) -> int:
        """鼠标点击查找区域"""
        if not self.simulator:
            return -1

        grid_x, grid_y, grid_w, grid_h = self._get_grid_area()
        mx, my = pos

        if not (grid_x <= mx <= grid_x + grid_w and grid_y <= my <= grid_y + grid_h):
            return -1

        zones = self.simulator.planet_zones
        cell_w = grid_w / zones.LONGITUDE_DIVISIONS
        cell_h = grid_h / zones.LATITUDE_DIVISIONS

        lon_i = int((mx - grid_x) / cell_w)
        lat_i = int((my - grid_y) / cell_h)

        lon_i = max(0, min(zones.LONGITUDE_DIVISIONS - 1, lon_i))
        lat_i = max(0, min(zones.LATITUDE_DIVISIONS - 1, lat_i))

        return lat_i * zones.LONGITUDE_DIVISIONS + lon_i

    def render(self, screen: pygame.Surface):
        """渲染"""
        if not self.visible:
            return

        screen.fill((10, 12, 20))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("区域浏览", True, (150, 220, 255))
            title_rect = title_surf.get_rect(center=(width // 2, max(35, int(45 * scale))))
            screen.blit(title_surf, title_rect)

        # 按钮
        self.back_button.render(screen)
        for i, btn in enumerate(self.mode_buttons):
            btn.render(screen)
            # 当前模式高亮
            if i == self.display_mode:
                pygame.draw.line(screen, (100, 200, 255),
                                 (btn.rect.left, btn.rect.bottom + 2),
                                 (btn.rect.right, btn.rect.bottom + 2), 3)

        if self.simulator:
            # 全球概览
            self._render_global_overview(screen, scale)
            # 区域网格
            self._render_zone_grid(screen, scale)
            # 详情面板
            if self.selected_zone_id >= 0:
                self._render_zone_detail(screen, scale)

        # 底部提示
        if 'tiny' in self.fonts:
            hint = self.fonts['tiny'].render(
                "点击区域查看详情 | TAB切换显示模式", True, (80, 100, 130)
            )
            screen.blit(hint, (width - hint.get_width() - 15, height - 22))

        # 消息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, (255, 200, 100))
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(40, int(50 * scale))))
            screen.blit(msg_surf, msg_rect)

    def _render_global_overview(self, screen: pygame.Surface, scale: float):
        """渲染全球概览数据"""
        if not self.simulator:
            return

        width = screen.get_width()
        zones = self.simulator.planet_zones
        avg = zones.get_average_environment()

        font = get_font(max(13, int(16 * scale)))
        y = max(75, int(90 * scale))
        x = int(width * 0.63)

        # 自转角度
        items = [
            (f"自转角度: {zones.rotation_angle:.1f}°", (180, 200, 255)),
            (f"全球平均温度: {avg['temperature']:.1f}℃", self._temp_color(avg['temperature'])),
            (f"全球平均辐射: {avg['radiation']:.2f}", self._rad_color(avg['radiation'])),
            (f"受光面区域: {len(zones.get_illuminated_zones())}/{zones.TOTAL_ZONES}",
             (255, 255, 150)),
        ]

        for text, color in items:
            surf = font.render(text, True, color)
            screen.blit(surf, (x, y))
            y += font.get_height() + 4

    def _render_zone_grid(self, screen: pygame.Surface, scale: float):
        """渲染区域网格"""
        if not self.simulator:
            return

        zones = self.simulator.planet_zones
        grid_x, grid_y, grid_w, grid_h = self._get_grid_area()

        cell_w = grid_w / zones.LONGITUDE_DIVISIONS
        cell_h = grid_h / zones.LATITUDE_DIVISIONS

        mouse_pos = pygame.mouse.get_pos()
        tiny_font = get_font(max(9, int(11 * scale)))
        small_font = get_font(max(11, int(13 * scale)))

        # 经度标签
        for lon_i in range(zones.LONGITUDE_DIVISIONS):
            x = grid_x + lon_i * cell_w + cell_w / 2
            deg = lon_i * 30
            label = tiny_font.render(f"{deg}°", True, (80, 100, 130))
            screen.blit(label, (int(x) - label.get_width() // 2, grid_y - 15))

        # 纬度标签
        for lat_i in range(zones.LATITUDE_DIVISIONS):
            y = grid_y + lat_i * cell_h + cell_h / 2
            deg = -90 + lat_i * 30 + 15
            label = tiny_font.render(f"{deg:.0f}°", True, (80, 100, 130))
            screen.blit(label, (grid_x - label.get_width() - 5, int(y) - label.get_height() // 2))

        for zone in zones.zones:
            cx = grid_x + zone.lon_index * cell_w
            cy = grid_y + zone.lat_index * cell_h
            rect = pygame.Rect(int(cx), int(cy), int(cell_w), int(cell_h))

            # 根据显示模式选择颜色
            if self.display_mode == self.MODE_TEMPERATURE:
                color = self._to_heatmap_color(zone.temperature, -200, 300)
            elif self.display_mode == self.MODE_RADIATION:
                color = self._to_heatmap_color(zone.radiation, 0, 20)
            else:
                color = self._to_light_color(zone.light_intensity)

            pygame.draw.rect(screen, color, rect)

            # 选中高亮
            if zone.zone_id == self.selected_zone_id:
                pygame.draw.rect(screen, (255, 255, 100), rect, 3)
            # 悬浮高亮
            elif rect.collidepoint(mouse_pos):
                pygame.draw.rect(screen, (200, 200, 255), rect, 2)
                # 悬浮信息
                if self.display_mode == self.MODE_TEMPERATURE:
                    val_text = f"{zone.temperature:.0f}℃"
                elif self.display_mode == self.MODE_RADIATION:
                    val_text = f"{zone.radiation:.1f}"
                else:
                    val_text = f"{zone.light_intensity:.0%}"
                val_surf = tiny_font.render(val_text, True, (255, 255, 200))
                screen.blit(val_surf, (rect.x + 2, rect.y + 2))
            else:
                pygame.draw.rect(screen, (30, 35, 50), rect, 1)

            # 建筑图标
            if zone.building_ids:
                mark = small_font.render("🏗", True, (255, 200, 100))
                screen.blit(mark, (rect.right - mark.get_width() - 2, rect.bottom - mark.get_height() - 2))

        # 显示模式标签
        mode_label = small_font.render(
            f"显示: {self.MODE_NAMES[self.display_mode]}", True, (150, 180, 220)
        )
        screen.blit(mode_label, (grid_x, grid_y + grid_h + 5))

    def _render_zone_detail(self, screen: pygame.Surface, scale: float):
        """渲染选中区域的详细信息面板"""
        if not self.simulator:
            return

        zone = self.simulator.planet_zones.get_zone(self.selected_zone_id)
        if not zone:
            return

        width, height = screen.get_size()
        panel_x = int(width * 0.63)
        panel_y = int(height * 0.35)
        panel_w = int(width * 0.34)
        panel_h = int(height * 0.58)

        # 面板背景
        panel_rect = pygame.Rect(panel_x, panel_y, panel_w, panel_h)
        bg_surf = pygame.Surface((panel_w, panel_h), pygame.SRCALPHA)
        bg_surf.fill((20, 25, 40, 220))
        screen.blit(bg_surf, (panel_x, panel_y))
        pygame.draw.rect(screen, (60, 80, 130), panel_rect, 2, border_radius=6)

        title_font = get_font(max(18, int(24 * scale)))
        font = get_font(max(14, int(17 * scale)))
        small_font = get_font(max(12, int(14 * scale)))

        x = panel_x + 15
        y = panel_y + 12

        # 区域标题
        title = f"区域 #{zone.zone_id}"
        title_surf = title_font.render(title, True, (200, 220, 255))
        screen.blit(title_surf, (x, y))
        y += title_font.get_height() + 8

        # 地理信息
        lines = [
            (f"纬度: {zone.lat_range[0]:.0f}° ~ {zone.lat_range[1]:.0f}°", (180, 200, 220)),
            (f"经度: {zone.lon_range[0]:.0f}° ~ {zone.lon_range[1]:.0f}°", (180, 200, 220)),
            (f"地形: {zone.terrain_type}", (180, 220, 180)),
            ("", None),
            ("─── 环境数据 ───", (120, 150, 200)),
            (f"温度: {zone.temperature:.1f} ℃", self._temp_color(zone.temperature)),
            (f"辐射: {zone.radiation:.2f}", self._rad_color(zone.radiation)),
            (f"光照: {zone.light_intensity:.0%}", (255, 255, 150)),
            (f"面积权重: {zone.area_weight:.2f}", (150, 150, 180)),
        ]

        for text, color in lines:
            if text and color:
                surf = font.render(text, True, color)
                screen.blit(surf, (x, y))
            y += font.get_height() + 3

        # 建筑列表
        y += 8
        buildings_header = font.render("─── 建筑 ───", True, (120, 150, 200))
        screen.blit(buildings_header, (x, y))
        y += font.get_height() + 4

        buildings_in_zone = self.simulator.entities.get_buildings_in_zone(zone.zone_id)
        if not buildings_in_zone:
            empty_surf = small_font.render("暂无建筑", True, (100, 100, 120))
            screen.blit(empty_surf, (x, y))
        else:
            for b in buildings_in_zone[:8]:  # 最多显示8个
                if b.destroyed:
                    status = "已损毁"
                    color = (255, 80, 80)
                elif b.durability < b.max_durability * 0.3:
                    status = f"耐久: {b.durability:.0f}/{b.max_durability:.0f}"
                    color = (255, 180, 80)
                else:
                    status = f"耐久: {b.durability:.0f}/{b.max_durability:.0f}"
                    color = (150, 255, 150)

                b_text = f"• {b.name} [{status}]"
                b_surf = small_font.render(b_text, True, color)
                screen.blit(b_surf, (x, y))
                y += small_font.get_height() + 2

            if len(buildings_in_zone) > 8:
                more = small_font.render(f"  ...还有 {len(buildings_in_zone) - 8} 座", True, (120, 120, 140))
                screen.blit(more, (x, y))

    # ── 颜色映射工具 ───────────────────────────────────────────

    def _to_heatmap_color(self, value: float, vmin: float, vmax: float) -> Tuple[int, int, int]:
        """将数值映射为热力图颜色（蓝->绿->黄->红）"""
        t = max(0, min(1, (value - vmin) / (vmax - vmin + 1e-6)))

        if t < 0.25:
            # 深蓝 -> 蓝
            s = t / 0.25
            return (20, int(40 + 80 * s), int(100 + 155 * s))
        elif t < 0.5:
            # 蓝 -> 绿
            s = (t - 0.25) / 0.25
            return (int(20 + 60 * s), int(120 + 135 * s), int(255 - 155 * s))
        elif t < 0.75:
            # 绿 -> 黄
            s = (t - 0.5) / 0.25
            return (int(80 + 175 * s), 255, int(100 - 100 * s))
        else:
            # 黄 -> 红
            s = (t - 0.75) / 0.25
            return (255, int(255 - 200 * s), int(0 + 20 * (1 - s)))

    def _to_light_color(self, value: float) -> Tuple[int, int, int]:
        """光照颜色映射"""
        v = max(0, min(1, value))
        return (int(20 + 235 * v), int(20 + 200 * v), int(40 + 80 * v))

    def _temp_color(self, temp: float) -> Tuple[int, int, int]:
        """温度数值颜色"""
        if temp < -50:
            return (100, 150, 255)
        elif temp > 60:
            return (255, 100, 100)
        else:
            return (100, 255, 100)

    def _rad_color(self, rad: float) -> Tuple[int, int, int]:
        """辐射数值颜色"""
        if rad > 10:
            return (255, 50, 50)
        elif rad > 2:
            return (255, 200, 50)
        return (100, 255, 100)
