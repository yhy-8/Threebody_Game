"""决策子界面 - 建筑建造和文明政策选择（原"政策系统"重构）"""

import pygame
from typing import Optional, List, Tuple

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font


class DecisionScreen(Screen):
    """决策系统子界面 — 分标签展示建筑建造和政策执行"""

    TAB_CONSTRUCTION = 0
    TAB_POLICY = 1

    # 子视图模式
    VIEW_LIST = 0       # 决策列表视图
    VIEW_ZONE_SELECT = 1  # 区域选择视图（全屏独立界面）

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.current_tab = self.TAB_CONSTRUCTION
        self.current_view = self.VIEW_LIST
        self.message = ""
        self.message_timer = 0.0
        self.message_color = (255, 200, 100)

        # 区域选择状态
        self.pending_decision_id: Optional[str] = None
        self.selected_zone_id: int = -1
        self.hovered_zone_id: int = -1

        # 滚动
        self.scroll_offset = 0
        self.max_scroll = 0

        # 按钮
        self.decision_buttons: List[Tuple[MenuButton, str]] = []

        # 区域选择视图的按钮
        self.zone_cancel_button: Optional[MenuButton] = None
        self.zone_confirm_button: Optional[MenuButton] = None

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

        # 标签切换按钮（第二行，避免与标题重叠）
        tab_y = int(20 * scale) + btn_h + int(15 * scale)
        tab_w = max(120, int(150 * scale))
        tab_x_start = int(20 * scale)

        self.tab_construction_btn = MenuButton(
            tab_x_start, tab_y, tab_w, btn_h,
            "建筑建造",
            callback=lambda: self.switch_tab(self.TAB_CONSTRUCTION),
            font_size=btn_font_size
        )
        self.tab_policy_btn = MenuButton(
            tab_x_start + tab_w + int(15 * scale), tab_y, tab_w, btn_h,
            "文明政策",
            callback=lambda: self.switch_tab(self.TAB_POLICY),
            font_size=btn_font_size
        )

        # 区域选择视图的按钮
        zone_btn_w = max(120, int(150 * scale))
        zone_btn_h = max(36, int(44 * scale))
        zone_btn_font = max(16, int(20 * scale))

        self.zone_cancel_button = MenuButton(
            int(20 * scale), int(20 * scale), zone_btn_w, zone_btn_h,
            "← 取消选择",
            callback=self._cancel_zone_select,
            font_size=zone_btn_font
        )

        # 确认按钮（右下角，在区域选择视图中动态定位）
        confirm_x = width - zone_btn_w - int(30 * scale)
        confirm_y = height - zone_btn_h - int(30 * scale)
        self.zone_confirm_button = MenuButton(
            confirm_x, confirm_y, zone_btn_w, zone_btn_h,
            "✓ 确认建造",
            callback=self._confirm_zone_select,
            font_size=zone_btn_font
        )

        self.load_fonts()

    def switch_tab(self, tab_id: int):
        """切换标签页"""
        self.current_tab = tab_id
        self.scroll_offset = 0
        self.current_view = self.VIEW_LIST
        self.pending_decision_id = None
        self.refresh_buttons()

    def refresh_buttons(self):
        """刷新决策按钮列表"""
        if not self.simulator:
            return
        self.decision_buttons = []

        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        dm = self.simulator.decision_manager
        if self.current_tab == self.TAB_CONSTRUCTION:
            decisions = dm.get_construction_decisions()
        else:
            decisions = dm.get_policy_decisions()

        start_y = max(160, int(height * 0.22))
        gap = max(75, int(90 * scale))
        btn_w = max(120, int(150 * scale))
        btn_h = max(36, int(42 * scale))

        for idx, decision in enumerate(decisions):
            btn_y = start_y + idx * gap - self.scroll_offset
            btn_x = int(width * 0.72)

            # 检查是否可执行
            can, reason = dm.can_execute(decision.id, self.simulator.entities, self.simulator.tech_tree)

            btn_text = "建造" if decision.category == "construction" else "执行"
            if not can:
                btn_text = "不可用"

            def make_callback(did):
                return lambda: self.on_decision(did)

            btn = MenuButton(
                btn_x, btn_y, btn_w, btn_h,
                btn_text,
                callback=make_callback(decision.id),
                font_size=max(14, int(18 * scale))
            )
            self.decision_buttons.append((btn, decision.id))

        self.max_scroll = max(0, len(decisions) * gap - (height - start_y - 100))

    def on_back(self):
        """返回主界面"""
        if self.current_view == self.VIEW_ZONE_SELECT:
            self._cancel_zone_select()
            return
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_decision(self, decision_id: str):
        """点击决策"""
        if not self.simulator:
            return

        dm = self.simulator.decision_manager
        decision = dm.available_decisions.get(decision_id)
        if not decision:
            return

        can, reason = dm.can_execute(decision_id, self.simulator.entities, self.simulator.tech_tree)
        if not can:
            self.message = f"无法执行：{reason}"
            self.message_color = (255, 100, 100)
            self.message_timer = 3.0
            return

        # 如果需要选择区域 → 切换到区域选择视图
        if decision.requires_zone:
            self.pending_decision_id = decision_id
            self.selected_zone_id = -1
            self.hovered_zone_id = -1
            self.current_view = self.VIEW_ZONE_SELECT
            self.message = ""
            self.message_timer = 0
            # 重新设置UI以更新按钮位置
            self.setup_ui()
            return

        # 直接执行
        success, msg, _ = dm.execute_decision(
            decision_id, self.simulator.entities,
            self.simulator.tech_tree, self.simulator.planet_zones
        )
        self.message = msg
        self.message_color = (150, 255, 150) if success else (255, 100, 100)
        self.message_timer = 3.0
        self.refresh_buttons()

    def _cancel_zone_select(self):
        """取消区域选择，返回决策列表"""
        self.current_view = self.VIEW_LIST
        self.pending_decision_id = None
        self.selected_zone_id = -1
        self.hovered_zone_id = -1
        self.message = ""
        self.message_timer = 0

    def _confirm_zone_select(self):
        """确认区域选择并执行建造"""
        if self.selected_zone_id < 0:
            self.message = "请先点击选择一个区域"
            self.message_color = (255, 200, 100)
            self.message_timer = 3.0
            return
        self._execute_zone_build(self.selected_zone_id)

    def _execute_zone_build(self, zone_id: int):
        """在选定区域执行建造"""
        if not self.pending_decision_id or not self.simulator:
            return

        dm = self.simulator.decision_manager
        success, msg, _ = dm.execute_decision(
            self.pending_decision_id, self.simulator.entities,
            self.simulator.tech_tree, self.simulator.planet_zones, zone_id
        )
        self.message = msg
        self.message_color = (150, 255, 150) if success else (255, 100, 100)
        self.message_timer = 3.0

        if success:
            # 建造成功，返回决策列表
            self.current_view = self.VIEW_LIST
            self.pending_decision_id = None
            self.selected_zone_id = -1
            self.refresh_buttons()
        # 如果失败，留在区域选择界面让用户重选

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.current_view = self.VIEW_LIST
        self.pending_decision_id = None
        self.selected_zone_id = -1
        self.setup_ui()
        self.refresh_buttons()

    def update(self, dt: float):
        """更新"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt

        if self.current_view == self.VIEW_LIST:
            self.back_button.update(dt)
            self.tab_construction_btn.update(dt)
            self.tab_policy_btn.update(dt)
            for btn, _ in self.decision_buttons:
                btn.update(dt)
        else:
            # 区域选择视图
            self.zone_cancel_button.update(dt)
            self.zone_confirm_button.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        if self.current_view == self.VIEW_ZONE_SELECT:
            return self._handle_zone_select_event(event)
        else:
            return self._handle_list_event(event)

    def _handle_list_event(self, event: pygame.event.Event) -> bool:
        """处理决策列表视图的事件"""
        if self.back_button.handle_event(event):
            return True
        if self.tab_construction_btn.handle_event(event):
            return True
        if self.tab_policy_btn.handle_event(event):
            return True

        # 滚轮滚动
        if event.type == pygame.MOUSEWHEEL:
            self.scroll_offset = max(0, min(self.max_scroll, self.scroll_offset - event.y * 30))
            self.refresh_buttons()
            return True

        for btn, _ in self.decision_buttons:
            if btn.handle_event(event):
                return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True

        return False

    def _handle_zone_select_event(self, event: pygame.event.Event) -> bool:
        """处理区域选择视图的事件"""
        if self.zone_cancel_button.handle_event(event):
            return True
        if self.zone_confirm_button.handle_event(event):
            return True

        # 鼠标移动 → 更新悬浮区域
        if event.type == pygame.MOUSEMOTION:
            self.hovered_zone_id = self._get_zone_at_mouse(event.pos)

        # 点击网格选择区域
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            zone_id = self._get_zone_at_mouse(event.pos)
            if zone_id >= 0:
                self.selected_zone_id = zone_id
                return True

        # 双击立即建造
        if event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            # pygame没有原生双击，用选中后再点击同一区域来触发
            pass

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self._cancel_zone_select()
                return True
            if event.key == pygame.K_RETURN and self.selected_zone_id >= 0:
                self._confirm_zone_select()
                return True

        return False

    def _get_zone_grid_area(self) -> Tuple[int, int, int, int]:
        """获取区域选择视图中的网格绘制区域"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        # 左侧留给纬度标签
        label_margin_left = max(50, int(60 * scale))
        # 顶部留给标题和经度标签
        top_margin = max(90, int(110 * scale))
        # 右侧留给信息面板
        right_panel_w = max(250, int(320 * scale))
        # 底部留给按钮和消息
        bottom_margin = max(80, int(100 * scale))

        grid_x = label_margin_left
        grid_y = top_margin
        grid_w = width - label_margin_left - right_panel_w - int(30 * scale)
        grid_h = height - top_margin - bottom_margin

        return grid_x, grid_y, max(200, grid_w), max(150, grid_h)

    def _get_zone_at_mouse(self, pos: Tuple[int, int]) -> int:
        """根据鼠标位置查找区域网格中的区域ID"""
        if not self.simulator:
            return -1

        grid_x, grid_y, grid_w, grid_h = self._get_zone_grid_area()

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

        zone_id = lat_i * zones.LONGITUDE_DIVISIONS + lon_i
        return zone_id

    # ── 渲染 ──────────────────────────────────────────────────────

    def render(self, screen: pygame.Surface):
        """渲染"""
        if not self.visible:
            return

        if self.current_view == self.VIEW_ZONE_SELECT:
            self._render_zone_select_view(screen)
        else:
            self._render_list_view(screen)

    def _render_list_view(self, screen: pygame.Surface):
        """渲染决策列表视图"""
        screen.fill((18, 14, 22))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 标题（右上角，避免与按钮重叠）
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("决策", True, (255, 200, 150))
            title_rect = title_surf.get_rect(topright=(width - int(30 * scale), int(20 * scale)))
            screen.blit(title_surf, title_rect)

        # 绘制标签指示器（当前选中的标签高亮）
        if self.current_tab == self.TAB_CONSTRUCTION:
            pygame.draw.line(screen, (100, 200, 255),
                             (self.tab_construction_btn.rect.left, self.tab_construction_btn.rect.bottom + 2),
                             (self.tab_construction_btn.rect.right, self.tab_construction_btn.rect.bottom + 2), 3)
        else:
            pygame.draw.line(screen, (255, 180, 100),
                             (self.tab_policy_btn.rect.left, self.tab_policy_btn.rect.bottom + 2),
                             (self.tab_policy_btn.rect.right, self.tab_policy_btn.rect.bottom + 2), 3)

        # 当前状态（标签按钮下方）
        if self.simulator and 'small' in self.fonts:
            dm = self.simulator.decision_manager
            state_text = f"文明状态: {dm.current_state.value.upper()}"
            state_surf = self.fonts['small'].render(state_text, True, (200, 200, 220))
            state_y = self.tab_construction_btn.rect.bottom + int(15 * scale)
            screen.blit(state_surf, (int(20 * scale), state_y))

        self.back_button.render(screen)
        self.tab_construction_btn.render(screen)
        self.tab_policy_btn.render(screen)

        # 渲染决策列表
        self._render_decision_list(screen, scale)

        # 提示信息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, self.message_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(30, int(40 * scale))))
            screen.blit(msg_surf, msg_rect)

    def _render_zone_select_view(self, screen: pygame.Surface):
        """渲染区域选择全屏视图"""
        screen.fill((12, 10, 18))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # ── 顶部标题栏 ──
        title_font = get_font(max(20, int(28 * scale)))
        subtitle_font = get_font(max(14, int(18 * scale)))

        # 获取待建造建筑信息
        building_name = "建筑"
        if self.simulator and self.pending_decision_id:
            dm = self.simulator.decision_manager
            decision = dm.available_decisions.get(self.pending_decision_id)
            if decision:
                building_name = decision.name

        title_text = f"选择建造区域 — {building_name}"
        title_surf = title_font.render(title_text, True, (100, 200, 255))
        title_x = max(200, int(250 * scale))
        screen.blit(title_surf, (title_x, int(25 * scale)))

        hint_text = "点击网格选择区域，然后点击「确认建造」"
        hint_surf = subtitle_font.render(hint_text, True, (120, 140, 170))
        screen.blit(hint_surf, (title_x, int(25 * scale) + title_font.get_height() + 4))

        # ── 区域网格（左侧主区域） ──
        self._render_zone_grid_full(screen, scale)

        # ── 右侧信息面板 ──
        self._render_zone_info_panel(screen, scale)

        # ── 按钮 ──
        self.zone_cancel_button.render(screen)
        if self.selected_zone_id >= 0:
            self.zone_confirm_button.render(screen)

        # ── 底部消息 ──
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, self.message_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(20, int(25 * scale))))
            screen.blit(msg_surf, msg_rect)

    def _render_zone_grid_full(self, screen: pygame.Surface, scale: float):
        """渲染完整的区域选择网格"""
        if not self.simulator:
            return

        zones = self.simulator.planet_zones
        grid_x, grid_y, grid_w, grid_h = self._get_zone_grid_area()

        cell_w = grid_w / zones.LONGITUDE_DIVISIONS
        cell_h = grid_h / zones.LATITUDE_DIVISIONS

        tiny_font = get_font(max(10, int(12 * scale)))
        small_font = get_font(max(11, int(13 * scale)))
        label_font = get_font(max(10, int(12 * scale)))

        # ── 经度标签（网格上方） ──
        for lon_i in range(zones.LONGITUDE_DIVISIONS):
            x = grid_x + lon_i * cell_w + cell_w / 2
            deg = lon_i * 30
            label = label_font.render(f"{deg}°", True, (80, 100, 140))
            screen.blit(label, (int(x) - label.get_width() // 2, grid_y - label_font.get_height() - 4))

        # ── 纬度标签（网格左侧） ──
        for lat_i in range(zones.LATITUDE_DIVISIONS):
            y = grid_y + lat_i * cell_h + cell_h / 2
            deg = -90 + lat_i * 30 + 15
            label = label_font.render(f"{deg:.0f}°", True, (80, 100, 140))
            screen.blit(label, (grid_x - label.get_width() - 8, int(y) - label.get_height() // 2))

        # ── 绘制网格单元 ──
        mouse_pos = pygame.mouse.get_pos()
        for zone in zones.zones:
            cx = grid_x + zone.lon_index * cell_w
            cy = grid_y + zone.lat_index * cell_h
            rect = pygame.Rect(int(cx), int(cy), max(1, int(cell_w)), max(1, int(cell_h)))

            # 温度颜色映射
            temp = zone.temperature
            if temp < -100:
                color = (25, 35, 75)
            elif temp < 0:
                t = (temp + 100) / 100
                color = (25 + int(35 * t), 35 + int(55 * t), 75 + int(55 * t))
            elif temp < 60:
                t = temp / 60
                color = (60 + int(70 * t), 90 + int(20 * t), 130 - int(70 * t))
            else:
                t = min(1, (temp - 60) / 200)
                color = (130 + int(125 * t), 70 - int(50 * t), 40 - int(30 * t))

            pygame.draw.rect(screen, color, rect)

            # 选中高亮（粗黄框 + 半透明覆盖）
            if zone.zone_id == self.selected_zone_id:
                highlight = pygame.Surface((rect.width, rect.height), pygame.SRCALPHA)
                highlight.fill((255, 255, 100, 40))
                screen.blit(highlight, rect.topleft)
                pygame.draw.rect(screen, (255, 255, 100), rect, 3)
            # 悬浮高亮
            elif rect.collidepoint(mouse_pos):
                hover_overlay = pygame.Surface((rect.width, rect.height), pygame.SRCALPHA)
                hover_overlay.fill((200, 200, 255, 30))
                screen.blit(hover_overlay, rect.topleft)
                pygame.draw.rect(screen, (180, 200, 255), rect, 2)
            else:
                pygame.draw.rect(screen, (30, 38, 55), rect, 1)

            # 已有建筑标记
            if zone.building_ids:
                count_surf = tiny_font.render(str(len(zone.building_ids)), True, (255, 200, 100))
                screen.blit(count_surf, (rect.right - count_surf.get_width() - 3,
                                         rect.bottom - count_surf.get_height() - 2))

    def _render_zone_info_panel(self, screen: pygame.Surface, scale: float):
        """渲染区域选择视图的右侧信息面板"""
        if not self.simulator:
            return

        width, height = screen.get_size()
        grid_x, grid_y, grid_w, grid_h = self._get_zone_grid_area()

        panel_x = grid_x + grid_w + int(20 * scale)
        panel_y = grid_y
        panel_w = width - panel_x - int(15 * scale)

        title_font = get_font(max(16, int(20 * scale)))
        font = get_font(max(13, int(16 * scale)))
        small_font = get_font(max(11, int(14 * scale)))

        y = panel_y

        # ── 待建造建筑信息 ──
        dm = self.simulator.decision_manager
        decision = dm.available_decisions.get(self.pending_decision_id) if self.pending_decision_id else None

        if decision:
            # 分隔线样式
            line_color = (50, 60, 90)

            header = title_font.render("── 建造信息 ──", True, (100, 180, 255))
            screen.blit(header, (panel_x, y))
            y += header.get_height() + 8

            name_surf = font.render(f"建筑: {decision.name}", True, (220, 220, 240))
            screen.blit(name_surf, (panel_x + 5, y))
            y += font.get_height() + 4

            desc_surf = small_font.render(decision.description, True, (140, 140, 160))
            screen.blit(desc_surf, (panel_x + 5, y))
            y += small_font.get_height() + 8

            # 资源消耗
            res_names = {"minerals": "矿物", "energy": "能源", "food": "食物"}
            cost_header = small_font.render("资源消耗:", True, (200, 180, 100))
            screen.blit(cost_header, (panel_x + 5, y))
            y += small_font.get_height() + 3

            for res, cost in decision.resource_cost.items():
                display = res_names.get(res, res)
                cost_surf = small_font.render(f"  {display}: {int(cost)}", True, (220, 200, 120))
                screen.blit(cost_surf, (panel_x + 5, y))
                y += small_font.get_height() + 2

            y += 12
            pygame.draw.line(screen, line_color, (panel_x, y), (panel_x + panel_w, y), 1)
            y += 12

        # ── 选中/悬浮区域信息 ──
        display_zone_id = self.selected_zone_id if self.selected_zone_id >= 0 else self.hovered_zone_id
        zones = self.simulator.planet_zones

        if display_zone_id >= 0:
            zone = zones.get_zone(display_zone_id)
            if zone:
                is_selected = (display_zone_id == self.selected_zone_id)
                label = "已选区域" if is_selected else "悬浮区域"
                label_color = (255, 255, 150) if is_selected else (150, 180, 220)

                zone_header = title_font.render(f"── {label} ──", True, label_color)
                screen.blit(zone_header, (panel_x, y))
                y += zone_header.get_height() + 8

                zone_id_surf = font.render(f"区域 #{zone.zone_id}", True, (200, 220, 255))
                screen.blit(zone_id_surf, (panel_x + 5, y))
                y += font.get_height() + 4

                info_lines = [
                    (f"纬度: {zone.lat_range[0]:.0f}° ~ {zone.lat_range[1]:.0f}°", (160, 180, 200)),
                    (f"经度: {zone.lon_range[0]:.0f}° ~ {zone.lon_range[1]:.0f}°", (160, 180, 200)),
                    (f"地形: {zone.terrain_type}", (160, 200, 160)),
                    (f"温度: {zone.temperature:.1f} ℃", self._temp_color(zone.temperature)),
                    (f"辐射: {zone.radiation:.2f}", self._rad_color(zone.radiation)),
                    (f"光照: {zone.light_intensity:.0%}", (255, 255, 150)),
                ]

                for text, color in info_lines:
                    surf = small_font.render(text, True, color)
                    screen.blit(surf, (panel_x + 5, y))
                    y += small_font.get_height() + 2

                # 已有建筑
                y += 6
                buildings_in_zone = self.simulator.entities.get_buildings_in_zone(zone.zone_id)
                if buildings_in_zone:
                    bld_header = small_font.render(f"已有建筑 ({len(buildings_in_zone)}):", True, (180, 160, 120))
                    screen.blit(bld_header, (panel_x + 5, y))
                    y += small_font.get_height() + 3
                    for b in buildings_in_zone[:4]:
                        b_color = (255, 80, 80) if b.destroyed else (150, 255, 150)
                        b_text = f"  • {b.name}"
                        b_surf = small_font.render(b_text, True, b_color)
                        screen.blit(b_surf, (panel_x + 5, y))
                        y += small_font.get_height() + 1
                    if len(buildings_in_zone) > 4:
                        more = small_font.render(f"    ...还有 {len(buildings_in_zone) - 4} 座", True, (100, 100, 120))
                        screen.blit(more, (panel_x + 5, y))
                else:
                    empty_surf = small_font.render("暂无建筑", True, (90, 90, 110))
                    screen.blit(empty_surf, (panel_x + 5, y))
        else:
            # 没有选中也没有悬浮
            hint = font.render("← 点击网格选择区域", True, (80, 100, 130))
            screen.blit(hint, (panel_x, y))

    def _render_decision_list(self, screen: pygame.Surface, scale: float):
        """渲染决策列表"""
        if not self.simulator:
            return

        width, height = screen.get_size()
        dm = self.simulator.decision_manager

        if self.current_tab == self.TAB_CONSTRUCTION:
            decisions = dm.get_construction_decisions()
        else:
            decisions = dm.get_policy_decisions()

        title_font = get_font(max(16, int(22 * scale)))
        desc_font = get_font(max(12, int(15 * scale)))
        cost_font = get_font(max(11, int(14 * scale)))

        start_y = max(160, int(height * 0.22))
        gap = max(75, int(90 * scale))
        x_left = int(width * 0.05)

        res_names = {"minerals": "矿物", "energy": "能源", "food": "食物"}

        for idx, decision in enumerate(decisions):
            y = start_y + idx * gap - self.scroll_offset

            if y < start_y - 20 or y > height - 50:
                continue

            # 检查可执行性
            can, _ = dm.can_execute(decision.id, self.simulator.entities, self.simulator.tech_tree)
            name_color = (220, 220, 240) if can else (100, 100, 120)

            # 名称
            name_surf = title_font.render(decision.name, True, name_color)
            screen.blit(name_surf, (x_left, y))

            # 描述
            desc_surf = desc_font.render(decision.description, True, (130, 130, 150))
            screen.blit(desc_surf, (x_left, y + title_font.get_height() + 2))

            # 资源消耗
            cost_parts = []
            for res, cost in decision.resource_cost.items():
                display = res_names.get(res, res)
                cost_parts.append(f"{display}:{int(cost)}")
            if cost_parts:
                cost_text = "消耗: " + " | ".join(cost_parts)
                cost_surf = cost_font.render(cost_text, True, (200, 180, 100))
                screen.blit(cost_surf, (x_left, y + title_font.get_height() + desc_font.get_height() + 4))

        # 按钮
        for btn, _ in self.decision_buttons:
            btn.render(screen)

    # ── 颜色工具 ─────────────────────────────────────────────────

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
