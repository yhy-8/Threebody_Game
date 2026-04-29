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
    右侧：选中区域的详细信息面板 + 全球概览
    顶部：返回按钮 + 模式切换 + 标题
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
        self.dynamic_buttons = []
        self.breeder_buttons = []

        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        self.scale = scale = min(width / 1280, height / 720)

        btn_font_size = max(16, int(22 * scale))
        btn_h = max(30, int(36 * scale))
        back_w = max(90, int(110 * scale))

        # 第一行：返回按钮
        row1_y = int(12 * scale)
        self.back_button = MenuButton(
            int(15 * scale), row1_y, back_w, btn_h,
            "← 返回",
            callback=self.on_back,
            font_size=btn_font_size
        )

        # 第一行：模式按钮（返回按钮右侧）
        mode_w = max(65, int(80 * scale))
        mode_x = int(15 * scale) + back_w + int(20 * scale)
        self.mode_buttons = []
        for i, mode_name in self.MODE_NAMES.items():
            btn = MenuButton(
                mode_x + i * (mode_w + int(8 * scale)), row1_y, mode_w, btn_h,
                mode_name,
                callback=lambda m=i: self.set_display_mode(m),
                font_size=max(14, int(18 * scale))
            )
            self.mode_buttons.append(btn)

        # 布局计算：网格区域（留足标签空间）
        self._header_h = row1_y + btn_h + int(15 * scale)  # 头部总高度

        self.load_fonts()

    def set_display_mode(self, mode: int):
        """切换显示模式"""
        self.display_mode = mode


    def _refresh_dynamic_buttons(self):
        self.dynamic_buttons.clear()
        self.breeder_buttons.clear()
        if not self.simulator:
            return
            
        width, height = self.screen.get_size()
        scale = self.scale
        panel_x = int(width * 0.58)
        panel_w = width - panel_x - int(15 * scale)
        
        # ── 生育按钮 ──
        y = self._header_h + 5
        font = get_font(max(14, int(17 * scale)))
        y += font.get_height() + 6
        small_font = get_font(max(12, int(14 * scale)))
        y += (small_font.get_height() + 3) * 6 # 5 lines + 1 extra
        
        btn_w = max(20, int(25 * scale))
        btn_h = max(20, int(25 * scale))
        
        btn_y = y - (small_font.get_height() + 3) # approximately on the last overview line
        
        def make_breeder_cb(amount):
            def cb():
                if amount > 0:
                    ok, msg = self.simulator.entities.assign_breeders(amount)
                else:
                    ok, msg = self.simulator.entities.unassign_breeders(-amount)
                self.message = msg
                self.message_timer = 2.0
            return cb
            
        self.breeder_buttons.append(MenuButton(panel_x + panel_w - btn_w * 2 - 10, btn_y, btn_w, btn_h, "-", callback=make_breeder_cb(-1), font_size=max(14, int(18*scale))))
        self.breeder_buttons.append(MenuButton(panel_x + panel_w - btn_w, btn_y, btn_w, btn_h, "+", callback=make_breeder_cb(1), font_size=max(14, int(18*scale))))
        
        if self.selected_zone_id < 0:
            return
            
        # ── 建筑按钮 ──
        y += 20 # after separator
        title_font = get_font(max(16, int(20 * scale)))
        y += title_font.get_height() + 6
        font = get_font(max(13, int(16 * scale)))
        y += (font.get_height() + 2) * 8 # 8 lines
        y += 6
        y += font.get_height() + 4 # header
        
        buildings = self.simulator.entities.get_buildings_in_zone(self.selected_zone_id)
        for b in buildings[:6]:
            btn_y = y
            def make_b_cb(bid, amount):
                def cb():
                    if amount > 0:
                        ok, msg = self.simulator.entities.assign_worker_to_building(bid, amount)
                    else:
                        ok, msg = self.simulator.entities.unassign_worker_from_building(bid, -amount)
                    self.message = msg
                    self.message_timer = 2.0
                return cb
            
            if b.worker_capacity > 0 and b.active and not b.destroyed:
                self.dynamic_buttons.append(MenuButton(panel_x + panel_w - btn_w * 2 - 10, btn_y, btn_w, btn_h, "-", callback=make_b_cb(b.id, -1), font_size=max(14, int(18*scale))))
                self.dynamic_buttons.append(MenuButton(panel_x + panel_w - btn_w, btn_y, btn_w, btn_h, "+", callback=make_b_cb(b.id, 1), font_size=max(14, int(18*scale))))
            y += small_font.get_height() + 2

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
        self._refresh_dynamic_buttons()
        self.setup_ui()

    def update(self, dt: float):
        """更新"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt
        self.back_button.update(dt)
        for btn in self.dynamic_buttons: btn.update(dt)
        for btn in self.breeder_buttons: btn.update(dt)

        for btn in self.mode_buttons:
            btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        if self.back_button.handle_event(event):
            return True
        for btn in self.dynamic_buttons:
            if btn.handle_event(event): return True
        for btn in self.breeder_buttons:
            if btn.handle_event(event): return True

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
                self._refresh_dynamic_buttons()
                return True

        return False

    def _get_grid_area(self) -> Tuple[int, int, int, int]:
        """获取网格绘制区域（已扣除标签空间）"""
        width, height = self.screen.get_size()
        scale = self.scale

        # 左侧留给纬度标签
        label_margin_left = max(45, int(55 * scale))
        # 顶部留给经度标签
        label_margin_top = max(18, int(22 * scale))

        grid_x = label_margin_left
        grid_y = self._header_h + label_margin_top
        # 右侧 40% 留给信息面板
        grid_w = int(width * 0.55) - label_margin_left
        grid_h = height - grid_y - max(35, int(45 * scale))  # 底部留边距

        return grid_x, grid_y, max(100, grid_w), max(100, grid_h)

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
        scale = self.scale

        # 标题（右上角）
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("区域浏览", True, (150, 220, 255))
            title_rect = title_surf.get_rect(topright=(width - int(20 * scale), int(12 * scale)))
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
            # 区域网格（左侧）
            self._render_zone_grid(screen, scale)
            # 右侧面板：全球概览 + 区域详情
            self._render_right_panel(screen, scale)

        # 底部提示
        if 'tiny' in self.fonts:
            hint = self.fonts['tiny'].render(
                "点击区域查看详情 | TAB切换显示模式", True, (80, 100, 130)
            )
            screen.blit(hint, (width - hint.get_width() - 15, height - 20))

        # 消息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, (255, 200, 100))
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(35, int(45 * scale))))
            screen.blit(msg_surf, msg_rect)

    def _render_right_panel(self, screen: pygame.Surface, scale: float):
        """渲染右侧信息面板（全球概览 + 区域详情）"""
        if not self.simulator:
            return

        width, height = screen.get_size()
        panel_x = int(width * 0.58)
        panel_y = self._header_h
        panel_w = width - panel_x - int(15 * scale)

        font = get_font(max(14, int(17 * scale)))
        small_font = get_font(max(12, int(14 * scale)))

        zones = self.simulator.planet_zones
        avg = zones.get_average_environment()

        # ── 全球概览区 ──
        y = panel_y + 5

        section_title = font.render("── 全球概览 ──", True, (120, 150, 200))
        screen.blit(section_title, (panel_x, y))
        y += font.get_height() + 6

        overview_items = [
            (f"自转角度: {zones.rotation_angle:.1f}°", (180, 200, 255)),
            (f"全球平均温度: {avg['temperature']:.1f}℃", self._temp_color(avg['temperature'])),
            (f"全球平均辐射: {avg['radiation']:.2f}", self._rad_color(avg['radiation'])),
            (f"总人口: {self.simulator.entities.population.total} | 闲置: {self.simulator.entities.get_idle_population()}", (200, 255, 200)),
            (f"生育分配: {self.simulator.entities.population.breeders} 人", (255, 150, 200)),
        ]

        for text, color in overview_items:
            surf = small_font.render(text, True, color)
            screen.blit(surf, (panel_x + 10, y))
            y += small_font.get_height() + 3


        for btn in self.breeder_buttons:
            btn.render(screen)
        for btn in self.dynamic_buttons:
            btn.render(screen)

        # ── 分隔线 ──
        y += 10
        pygame.draw.line(screen, (40, 50, 70), (panel_x, y), (panel_x + panel_w, y), 1)
        y += 10

        # ── 区域详情区 ──
        if self.selected_zone_id >= 0:
            zone = zones.get_zone(self.selected_zone_id)
            if zone:
                self._render_zone_info(screen, zone, panel_x, y, panel_w, scale)
        else:
            hint = small_font.render("← 点击左侧网格选择区域", True, (80, 100, 130))
            screen.blit(hint, (panel_x + 10, y))

    def _render_zone_info(self, screen: pygame.Surface, zone, panel_x: int,
                          start_y: int, panel_w: int, scale: float):
        """渲染选中区域的详细信息"""
        title_font = get_font(max(16, int(20 * scale)))
        font = get_font(max(13, int(16 * scale)))
        small_font = get_font(max(11, int(13 * scale)))

        x = panel_x + 10
        y = start_y

        # 区域标题
        title = f"区域 #{zone.zone_id}"
        title_surf = title_font.render(title, True, (200, 220, 255))
        screen.blit(title_surf, (x, y))
        y += title_font.get_height() + 6

        # 信息行
        lines = [
            (f"纬度: {zone.lat_range[0]:.0f}° ~ {zone.lat_range[1]:.0f}°", (180, 200, 220)),
            (f"经度: {zone.lon_range[0]:.0f}° ~ {zone.lon_range[1]:.0f}°", (180, 200, 220)),
            (f"地形: {zone.terrain_type}", (180, 220, 180)),
            ("", None),
            (f"温度: {zone.temperature:.1f} ℃", self._temp_color(zone.temperature)),
            (f"辐射: {zone.radiation:.2f}", self._rad_color(zone.radiation)),
            (f"光照: {zone.light_intensity:.0%}", (255, 255, 150)),
            (f"面积权重: {zone.area_weight:.2f}", (150, 150, 180)),
        ]

        for text, color in lines:
            if text and color:
                surf = font.render(text, True, color)
                screen.blit(surf, (x, y))
            y += font.get_height() + 2

        # 建筑列表
        y += 6
        buildings_header = font.render("── 建筑 ──", True, (120, 150, 200))
        screen.blit(buildings_header, (x, y))
        y += font.get_height() + 4

        buildings_in_zone = self.simulator.entities.get_buildings_in_zone(zone.zone_id)
        if not buildings_in_zone:
            empty_surf = small_font.render("暂无建筑", True, (100, 100, 120))
            screen.blit(empty_surf, (x, y))
        else:
            for b in buildings_in_zone[:6]:
                if b.destroyed:
                    status = "已损毁"
                    color = (255, 80, 80)
                elif b.durability < b.max_durability * 0.3:
                    status = f"耐久:{b.durability:.0f}/{b.max_durability:.0f}"
                    color = (255, 180, 80)
                else:
                    status = f"耐久:{b.durability:.0f}/{b.max_durability:.0f}"
                    color = (150, 255, 150)

                workers = f"({b.assigned_workers}/{b.worker_capacity})" if b.worker_capacity > 0 else ""
                b_text = f"• {b.name} [{status}] {workers}"
                b_surf = small_font.render(b_text, True, color)
                screen.blit(b_surf, (x, y))
                y += small_font.get_height() + 2

            if len(buildings_in_zone) > 6:
                more = small_font.render(f"  ...还有 {len(buildings_in_zone) - 6} 座", True, (120, 120, 140))
                screen.blit(more, (x, y))

    def _render_zone_grid(self, screen: pygame.Surface, scale: float):
        """渲染区域网格"""
        if not self.simulator:
            return

        zones = self.simulator.planet_zones
        grid_x, grid_y, grid_w, grid_h = self._get_grid_area()

        cell_w = grid_w / zones.LONGITUDE_DIVISIONS
        cell_h = grid_h / zones.LATITUDE_DIVISIONS

        mouse_pos = pygame.mouse.get_pos()
        tiny_font = get_font(max(10, int(12 * scale)))
        small_font = get_font(max(11, int(13 * scale)))

        # 经度标签（网格上方）
        for lon_i in range(zones.LONGITUDE_DIVISIONS):
            x = grid_x + lon_i * cell_w + cell_w / 2
            deg = lon_i * 30
            label = tiny_font.render(f"{deg}°", True, (100, 120, 160))
            screen.blit(label, (int(x) - label.get_width() // 2, grid_y - tiny_font.get_height() - 3))

        # 纬度标签（网格左侧）
        for lat_i in range(zones.LATITUDE_DIVISIONS):
            y = grid_y + lat_i * cell_h + cell_h / 2
            deg = -90 + lat_i * 30 + 15
            label = tiny_font.render(f"{deg:.0f}°", True, (100, 120, 160))
            screen.blit(label, (grid_x - label.get_width() - 6, int(y) - label.get_height() // 2))

        # 绘制网格单元
        for zone in zones.zones:
            cx = grid_x + zone.lon_index * cell_w
            cy = grid_y + zone.lat_index * cell_h
            rect = pygame.Rect(int(cx), int(cy), max(1, int(cell_w)), max(1, int(cell_h)))

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

            # 建筑数量标记
            if zone.building_ids:
                count_surf = tiny_font.render(str(len(zone.building_ids)), True, (255, 200, 100))
                screen.blit(count_surf, (rect.right - count_surf.get_width() - 2,
                                         rect.bottom - count_surf.get_height() - 2))

    # ── 颜色映射工具 ───────────────────────────────────────────

    def _to_heatmap_color(self, value: float, vmin: float, vmax: float) -> Tuple[int, int, int]:
        """将数值映射为热力图颜色（蓝->绿->黄->红）"""
        t = max(0, min(1, (value - vmin) / (vmax - vmin + 1e-6)))

        if t < 0.25:
            s = t / 0.25
            return (20, int(40 + 80 * s), int(100 + 155 * s))
        elif t < 0.5:
            s = (t - 0.25) / 0.25
            return (int(20 + 60 * s), int(120 + 135 * s), int(255 - 155 * s))
        elif t < 0.75:
            s = (t - 0.5) / 0.25
            return (int(80 + 175 * s), 255, int(100 - 100 * s))
        else:
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
