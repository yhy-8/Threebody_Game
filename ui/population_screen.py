"""人口管理界面 - 岗位分配与概览"""

import pygame
from typing import Optional, List, Tuple

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font
from game.entities import JOB_TYPES


class PopulationScreen(Screen):
    """人口管理界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.simulator = None
        self.message = ""
        self.message_timer = 0.0
        
        self.job_buttons: List[tuple] = []
        
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
        self.refresh_buttons()

    def refresh_buttons(self):
        """刷新岗位加减按钮"""
        if not self.simulator:
            return
            
        self.job_buttons.clear()
        
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)
        
        start_y = max(150, int(height * 0.25))
        gap = max(45, int(55 * scale))
        
        btn_w = max(40, int(40 * scale))
        btn_h = max(30, int(35 * scale))
        
        col_x = width // 2 + int(100 * scale)
        
        idx = 0
        for job_id, job_name in JOB_TYPES.items():
            y = start_y + idx * gap
            
            # 减号按钮
            def make_sub_callback(jid):
                return lambda: self._adjust_job(jid, -1)
                
            sub_btn = MenuButton(
                col_x, y, btn_w, btn_h, "-",
                callback=make_sub_callback(job_id),
                font_size=max(18, int(24 * scale))
            )
            
            # 加号按钮
            def make_add_callback(jid):
                return lambda: self._adjust_job(jid, 1)
                
            add_btn = MenuButton(
                col_x + btn_w + max(60, int(80 * scale)), y, btn_w, btn_h, "+",
                callback=make_add_callback(job_id),
                font_size=max(18, int(24 * scale))
            )
            
            self.job_buttons.append((sub_btn, add_btn, job_id))
            idx += 1

    def _adjust_job(self, job_id: str, amount: int):
        """调整岗位人数"""
        if not self.simulator:
            return
            
        pop_manager = self.simulator.entities.population
        
        if amount > 0:
            success, msg = pop_manager.assign(job_id, amount)
        else:
            success, msg = pop_manager.unassign(job_id, -amount)
            
        self.message = msg
        self.message_color = (150, 255, 150) if success else (255, 100, 100)
        self.message_timer = 2.0

    def on_back(self):
        """返回主界面"""
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.setup_ui()

    def update(self, dt: float):
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt

        self.back_button.update(dt)
        for sub_btn, add_btn, _ in self.job_buttons:
            sub_btn.update(dt)
            add_btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        if not self.active:
            return False

        if self.back_button.handle_event(event):
            return True

        for sub_btn, add_btn, _ in self.job_buttons:
            if sub_btn.handle_event(event):
                return True
            if add_btn.handle_event(event):
                return True

        if event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
            self.on_back()
            return True

        return False

    def render(self, screen: pygame.Surface):
        if not self.visible:
            return

        screen.fill((15, 18, 25))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("人口管理", True, (255, 150, 200))
            title_rect = title_surf.get_rect(topright=(width - int(30 * scale), int(20 * scale)))
            screen.blit(title_surf, title_rect)

        self.back_button.render(screen)
        
        if not self.simulator:
            return

        pop_manager = self.simulator.entities.population
        
        # 总人口与闲置概览
        font_large = get_font(max(24, int(32 * scale)))
        font_normal = get_font(max(16, int(22 * scale)))
        
        y_overview = int(100 * scale)
        total_text = f"总人口: {pop_manager.total}"
        idle_text = f"闲置人口: {pop_manager.get_idle()}"
        
        t_surf = font_large.render(total_text, True, (200, 220, 255))
        i_surf = font_large.render(idle_text, True, (255, 200, 100) if pop_manager.get_idle() > 0 else (150, 150, 150))
        
        screen.blit(t_surf, (width // 2 - int(250 * scale), y_overview))
        screen.blit(i_surf, (width // 2 + int(50 * scale), y_overview))

        # 岗位列表
        start_y = max(150, int(height * 0.25))
        gap = max(45, int(55 * scale))
        x_left = width // 2 - int(250 * scale)
        col_x = width // 2 + int(100 * scale)
        btn_w = max(40, int(40 * scale))

        idx = 0
        for sub_btn, add_btn, job_id in self.job_buttons:
            y = start_y + idx * gap
            
            # 岗位名称
            job_name = JOB_TYPES[job_id]
            name_surf = font_normal.render(job_name, True, (180, 200, 220))
            screen.blit(name_surf, (x_left, y + 5))
            
            # 当前分配人数
            assigned = pop_manager.get_assigned(job_id)
            count_surf = font_normal.render(f"{assigned} 人", True, (255, 255, 255))
            count_rect = count_surf.get_rect(center=(col_x + btn_w + max(30, int(40 * scale)), y + btn_h // 2))
            screen.blit(count_surf, count_rect)
            
            # 按钮
            sub_btn.render(screen)
            add_btn.render(screen)
            
            idx += 1

        # 提示信息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, self.message_color)
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(40, int(50 * scale))))
            screen.blit(msg_surf, msg_rect)
