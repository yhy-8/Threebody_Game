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

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.current_tab = self.TAB_CONSTRUCTION
        self.message = ""
        self.message_timer = 0.0
        self.message_color = (255, 200, 100)

        # 区域选择状态
        self.selecting_zone = False
        self.pending_decision_id: Optional[str] = None
        self.selected_zone_id: int = -1

        # 滚动
        self.scroll_offset = 0
        self.max_scroll = 0

        # 按钮
        self.decision_buttons: List[Tuple[MenuButton, str]] = []

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

        self.load_fonts()

    def switch_tab(self, tab_id: int):
        """切换标签页"""
        self.current_tab = tab_id
        self.scroll_offset = 0
        self.selecting_zone = False
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
        if self.selecting_zone:
            self.selecting_zone = False
            self.pending_decision_id = None
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

        # 如果需要选择区域
        if decision.requires_zone:
            self.selecting_zone = True
            self.pending_decision_id = decision_id
            self.message = "请在下方网格中点击选择建造区域"
            self.message_color = (100, 200, 255)
            self.message_timer = 5.0
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

    def on_zone_selected(self, zone_id: int):
        """区域选择完成"""
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
        self.selecting_zone = False
        self.pending_decision_id = None
        self.refresh_buttons()

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.selecting_zone = False
        self.pending_decision_id = None
        self.setup_ui()
        self.refresh_buttons()

    def update(self, dt: float):
        """更新"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt
        self.back_button.update(dt)
        self.tab_construction_btn.update(dt)
        self.tab_policy_btn.update(dt)
        for btn, _ in self.decision_buttons:
            btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

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

        # 区域选择模式的点击处理
        if self.selecting_zone and event.type == pygame.MOUSEBUTTONDOWN and event.button == 1:
            zone_id = self._get_zone_at_mouse(event.pos)
            if zone_id >= 0:
                self.on_zone_selected(zone_id)
                return True

        for btn, _ in self.decision_buttons:
            if btn.handle_event(event):
                return True

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True

        return False

    def _get_zone_at_mouse(self, pos: Tuple[int, int]) -> int:
        """根据鼠标位置查找区域网格中的区域ID"""
        if not self.simulator:
            return -1

        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        # 区域网格的绘制区域
        grid_x = int(width * 0.05)
        grid_y = int(height * 0.55)
        grid_w = int(width * 0.6)
        grid_h = int(height * 0.38)

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

    def render(self, screen: pygame.Surface):
        """渲染"""
        if not self.visible:
            return

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

        # 区域选择模式：绘制区域网格
        if self.selecting_zone:
            self._render_zone_grid(screen, scale)

        # 提示信息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, self.message_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(30, int(40 * scale))))
            screen.blit(msg_surf, msg_rect)

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

    def _render_zone_grid(self, screen: pygame.Surface, scale: float):
        """渲染区域选择网格"""
        if not self.simulator:
            return

        width, height = screen.get_size()
        zones = self.simulator.planet_zones

        grid_x = int(width * 0.05)
        grid_y = int(height * 0.55)
        grid_w = int(width * 0.6)
        grid_h = int(height * 0.38)

        cell_w = grid_w / zones.LONGITUDE_DIVISIONS
        cell_h = grid_h / zones.LATITUDE_DIVISIONS

        # 标题
        label_font = get_font(max(14, int(18 * scale)))
        label = label_font.render("▼ 选择建造区域（点击格子）", True, (100, 200, 255))
        screen.blit(label, (grid_x, grid_y - 25))

        # 绘制网格
        mouse_pos = pygame.mouse.get_pos()
        small_font = get_font(max(10, int(12 * scale)))

        for zone in zones.zones:
            cx = grid_x + zone.lon_index * cell_w
            cy = grid_y + zone.lat_index * cell_h
            rect = pygame.Rect(int(cx), int(cy), int(cell_w), int(cell_h))

            # 颜色映射（温度）
            temp = zone.temperature
            if temp < -100:
                color = (30, 40, 80)
            elif temp < 0:
                t = (temp + 100) / 100
                color = (30 + int(40 * t), 40 + int(60 * t), 80 + int(60 * t))
            elif temp < 60:
                t = temp / 60
                color = (70 + int(80 * t), 100, 140 - int(80 * t))
            else:
                t = min(1, (temp - 60) / 200)
                color = (150 + int(105 * t), 80 - int(60 * t), 40 - int(30 * t))

            pygame.draw.rect(screen, color, rect)

            # 悬浮高亮
            if rect.collidepoint(mouse_pos):
                pygame.draw.rect(screen, (255, 255, 100), rect, 2)
                # 显示区域信息
                info = f"区域{zone.zone_id} {zone.terrain_type} {temp:.0f}℃"
                info_surf = small_font.render(info, True, (255, 255, 200))
                screen.blit(info_surf, (rect.x, rect.y - 15))
            else:
                pygame.draw.rect(screen, (40, 50, 70), rect, 1)

            # 建筑数量标记
            if zone.building_ids:
                count_surf = small_font.render(str(len(zone.building_ids)), True, (255, 200, 100))
                screen.blit(count_surf, (rect.x + 2, rect.y + 2))
