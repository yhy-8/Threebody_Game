"""政策子界面"""

import pygame
from typing import Optional

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font

class PolicyScreen(Screen):
    """政策系统子界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.setup_ui()
        self.message = ""
        self.message_timer = 0

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)
        
        btn_font_size = max(16, int(22 * scale))
        btn_h = max(32, int(40 * scale))
        btn_w_back = max(100, int(120 * scale))

        self.back_button = MenuButton(
            int(20 * scale), int(20 * scale), btn_w_back, btn_h,
            "← 返回",
            callback=self.on_back,
            font_size=btn_font_size
        )
        
        self.policy_buttons = []
        self.load_fonts()

    def refresh_policy_buttons(self):
        """构建政策按钮"""
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)
        self.policy_buttons = []
        
        start_y = max(150, int(height * 0.25))
        gap = max(110, int(130 * scale))
        btn_x = width // 2 - max(100, int(120 * scale)) // 2
        
        policies = [
            ("dehydrate", "全民脱水", "应对极其恶劣的环境，大部分建筑停工。"),
            ("rehydrate", "浸泡复苏", "文明重新激活，恢复正常的建设与繁衍。"),
            ("boom", "大生育计划", "在恒纪元中快速增加人口，需要消耗大量食物(至少500)。")
        ]
        
        for idx, (pid, name, desc) in enumerate(policies):
            btn_y = start_y + idx * gap
            
            def make_callback(nid):
                return lambda: self.on_policy(nid)
                
            btn = MenuButton(
                width // 2 - max(120, int(150 * scale)), btn_y, 
                max(240, int(300 * scale)), max(45, int(50 * scale)),
                name,
                callback=make_callback(pid),
                font_size=max(20, int(26 * scale))
            )
            self.policy_buttons.append((btn, pid, desc))

    def on_back(self):
        """返回主界面"""
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_policy(self, policy_id: str):
        """点击政策"""
        if not self.simulator:
            return
            
        policy_manager = self.simulator.policy_manager
        state = self.simulator.get_state()
        entities_state = state.get("entities", {})
        
        success, reason = policy_manager.enact_policy(policy_id, entities_state)
        self.message = reason
        self.message_timer = 3.0

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面时响应"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.setup_ui()
        self.refresh_policy_buttons()

    def update(self, dt: float):
        """更新"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt
            
        self.back_button.update(dt)
        for btn, _, _ in self.policy_buttons:
            btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False
            
        if self.back_button.handle_event(event):
            return True
            
        for btn, _, _ in self.policy_buttons:
            if btn.handle_event(event):
                return True
                
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True
        return False

    def render(self, screen: pygame.Surface):
        """渲染"""
        if not self.visible:
            return

        screen.fill((20, 15, 20))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("政策系统", True, (255, 180, 150))
            title_rect = title_surf.get_rect(center=(width // 2, max(60, int(80 * scale))))
            screen.blit(title_surf, title_rect)

        # 当前状态
        if self.simulator and 'normal' in self.fonts:
            state_val = self.simulator.policy_manager.current_state.value
            state_surf = self.fonts['normal'].render(f"当前整体状态: {state_val.upper()}", True, (255, 255, 255))
            screen.blit(state_surf, (width // 2 - state_surf.get_width() // 2, max(100, int(130 * scale))))

        self.back_button.render(screen)
        
        desc_font = get_font(max(14, int(18 * scale)))
        
        for btn, _, desc in self.policy_buttons:
            btn.render(screen)
            # 绘制描述在按钮下方
            desc_surf = desc_font.render(desc, True, (150, 150, 150))
            desc_rect = desc_surf.get_rect(center=(btn.rect.centerx, btn.rect.bottom + 25))
            screen.blit(desc_surf, desc_rect)

        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_color = (150, 255, 150) if "成功" in self.message or "完成" in self.message or "已开启" in self.message else (255, 100, 100)
            msg_surf = self.fonts['normal'].render(self.message, True, msg_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(40, int(60 * scale))))
            screen.blit(msg_surf, msg_rect)
