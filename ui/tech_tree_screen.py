"""科技树子界面"""

import pygame
from typing import Optional

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton
from render.ui import get_font

class TechTreeScreen(Screen):
    """科技树专属子界面"""

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

        # 返回按钮
        self.back_button = MenuButton(
            int(20 * scale), int(20 * scale), btn_w_back, btn_h,
            "← 返回",
            callback=self.on_back,
            font_size=btn_font_size
        )
        
        self.lock_buttons = []
        self.load_fonts()
        
    def refresh_tech_buttons(self):
        """刷新科技研发按钮列表"""
        if not self.simulator:
            return
            
        width, height = self.screen.get_size()
        scale = min(width / 1280, height / 720)
        self.lock_buttons = []
        
        tech_tree = self.simulator.tech_tree
        state = self.simulator.get_state()
        entities_state = state.get("entities", {})
        
        start_y = max(120, int(height * 0.2))
        gap = max(100, int(120 * scale))
        
        idx = 0
        for node_id, node in tech_tree.nodes.items():
            btn_x = int(width * 0.7)
            btn_y = start_y + idx * gap + 10
            
            btn_text = "已解锁" if node.unlocked else "研发"
            
            # 使用闭包绑定当前节点ID
            def make_callback(nid):
                return lambda: self.on_research(nid)
                
            btn = MenuButton(
                btn_x, btn_y, max(100, int(120 * scale)), max(36, int(40 * scale)),
                btn_text,
                callback=make_callback(node_id),
                font_size=max(16, int(22 * scale))
            )
            self.lock_buttons.append((btn, node_id))
            idx += 1

    def on_back(self):
        """返回主界面"""
        self.screen_manager.switch_to(ScreenType.MAIN_SCREEN)

    def on_research(self, node_id: str):
        """点击研发按钮"""
        if not self.simulator:
            return
        tech_tree = self.simulator.tech_tree
        state = self.simulator.get_state()
        entities_state = state.get("entities", {})
        
        can_unlock, reason = tech_tree.can_unlock(node_id, entities_state)
        
        if can_unlock:
            tech_tree.unlock_tech(node_id)
            self.message = f"成功解锁科技：{tech_tree.get_node(node_id).name}"
            self.message_timer = 3.0
            self.refresh_tech_buttons()
        else:
            self.message = f"无法研发：{reason}"
            self.message_timer = 3.0

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面时响应"""
        super().on_enter(previous_screen, **kwargs)
        self.screen = pygame.display.get_surface()
        self.rect = self.screen.get_rect()
        
        # 获取simulator
        self.simulator = self.screen_manager.global_state.get('simulator')
        self.setup_ui()
        self.refresh_tech_buttons()

    def update(self, dt: float):
        """更新状态"""
        super().update(dt)
        if self.message_timer > 0:
            self.message_timer -= dt
            
        self.back_button.update(dt)
        for btn, _ in self.lock_buttons:
            btn.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """事件处理"""
        if not self.active:
            return False
            
        if self.back_button.handle_event(event):
            return True
            
        for btn, _ in self.lock_buttons:
            if btn.handle_event(event):
                return True
                
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_back()
                return True
        return False

    def render(self, screen: pygame.Surface):
        """界面渲染"""
        if not self.visible:
            return

        screen.fill((15, 20, 30))
        width, height = screen.get_size()
        scale = min(width / 1280, height / 720)

        # 标题
        if 'title' in self.fonts:
            title_surf = self.fonts['title'].render("科技树", True, (150, 200, 255))
            title_rect = title_surf.get_rect(center=(width // 2, max(60, int(80 * scale))))
            screen.blit(title_surf, title_rect)

        # 按钮
        self.back_button.render(screen)
        
        # 渲染各科技节点
        if self.simulator:
            tech_tree = self.simulator.tech_tree
            title_font = get_font(max(20, int(28 * scale)))
            desc_font = get_font(max(14, int(18 * scale)))
            
            start_y = max(120, int(height * 0.2))
            gap = max(100, int(120 * scale))
            
            idx = 0
            for node_id, node in tech_tree.nodes.items():
                y = start_y + idx * gap
                x = max(50, int(width * 0.2))
                
                # 名称和颜色
                color = (150, 255, 150) if node.unlocked else (200, 200, 200)
                name_surf = title_font.render(f"[{node.name}]", True, color)
                screen.blit(name_surf, (x, y))
                
                # 绘制依赖要求提示
                req_text = f"人口要求: {node.requirements.get('population', 0)}"
                if node.prerequisites:
                    pre_names = [tech_tree.get_node(pid).name for pid in node.prerequisites if tech_tree.get_node(pid)]
                    req_text += f" | 前置: {','.join(pre_names)}"
                
                desc_surf = desc_font.render(f"{node.description} ({req_text})", True, (150, 150, 150))
                desc_y_offset = title_font.get_height() + 10
                screen.blit(desc_surf, (x, y + desc_y_offset))
                
                idx += 1
                
            for btn, _ in self.lock_buttons:
                btn.render(screen)

        # 渲染提示信息
        if self.message_timer > 0 and 'normal' in self.fonts:
            msg_surf = self.fonts['normal'].render(self.message, True, (255, 200, 100))
            msg_rect = msg_surf.get_rect(center=(width // 2, height - max(40, int(60 * scale))))
            screen.blit(msg_surf, msg_rect)
