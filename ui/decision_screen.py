"""决策子界面 - 文明政策选择（原包含建筑建造，现已拆分）"""

import pygame
from typing import Optional, List, Tuple

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font
from game.entities import RESOURCE_DISPLAY_NAMES


class DecisionScreen(Screen):
    """决策系统子界面 — 展示并执行文明政策"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.message = ""
        self.message_timer = 0.0
        self.message_color = (255, 200, 100)

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

        self.load_fonts()

    def refresh_buttons(self):
        """刷新决策按钮列表"""
        if not self.simulator:
            return
        self.decision_buttons = []

        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)

        dm = self.simulator.decision_manager
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

            btn_text = "执行"
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
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_decision(self, decision_id: str):
        """点击执行政策"""
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

        # 直接执行
        success, msg, _ = dm.execute_decision(
            decision_id, self.simulator.entities,
            self.simulator.tech_tree, self.simulator.planet_zones
        )
        self.message = msg
        self.message_color = (150, 255, 150) if success else (255, 100, 100)
        self.message_timer = 3.0
        self.refresh_buttons()

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.setup_ui()
        self.refresh_buttons()

    def update(self, dt: float):
        """更新"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt

        self.back_button.update(dt)
        for btn, _ in self.decision_buttons:
            btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        if self.back_button.handle_event(event):
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

    def render(self, screen: pygame.Surface):
        """渲染决策列表视图"""
        if not self.visible:
            return

        screen.fill((18, 14, 22))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("文明政策", True, (255, 200, 150))
            title_rect = title_surf.get_rect(topright=(width - int(30 * scale), int(20 * scale)))
            screen.blit(title_surf, title_rect)

        # 当前状态
        if self.simulator and 'small' in self.fonts:
            dm = self.simulator.decision_manager
            state_text = f"文明状态: {dm.current_state.value.upper()}"
            state_surf = self.fonts['small'].render(state_text, True, (200, 200, 220))
            state_y = int(60 * scale)
            screen.blit(state_surf, (int(20 * scale), state_y))

        self.back_button.render(screen)

        # 渲染决策列表
        self._render_decision_list(screen, scale)

        # 提示信息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, self.message_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(30, int(40 * scale))))
            screen.blit(msg_surf, msg_rect)

    def _render_decision_list(self, screen: pygame.Surface, scale: float):
        """渲染政策列表"""
        if not self.simulator:
            return

        width, height = screen.get_size()
        dm = self.simulator.decision_manager
        decisions = dm.get_policy_decisions()

        title_font = get_font(max(16, int(22 * scale)))
        desc_font = get_font(max(12, int(15 * scale)))
        cost_font = get_font(max(11, int(14 * scale)))

        start_y = max(160, int(height * 0.22))
        gap = max(75, int(90 * scale))
        x_left = int(width * 0.05)

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
                display = RESOURCE_DISPLAY_NAMES.get(res, res)
                cost_parts.append(f"{display}:{int(cost)}")
            if cost_parts:
                cost_text = "消耗: " + " | ".join(cost_parts)
                cost_surf = cost_font.render(cost_text, True, (200, 180, 100))
                screen.blit(cost_surf, (x_left, y + title_font.get_height() + desc_font.get_height() + 4))

        # 按钮
        for btn, _ in self.decision_buttons:
            btn.render(screen)
