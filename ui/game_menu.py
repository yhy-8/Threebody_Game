"""游戏内菜单 - 游戏过程中按ESC打开的菜单"""

import pygame
from typing import Optional, List

from .screen_manager import Screen, ScreenType
from .initial_menu import MenuButton


class GameMenu(Screen):
    """游戏内菜单界面"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.buttons: List[MenuButton] = []
        self.overlay_alpha = 0.0
        self.menu_y_offset = -50
        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        width, height = self.screen.get_size()

        button_width = 280
        button_height = 55
        button_x = width // 2 - button_width // 2
        start_y = height // 2 - 120
        gap = 70

        self.buttons = [
            MenuButton(
                button_x, start_y,
                button_width, button_height,
                "继续游戏",
                callback=self.on_resume,
                font_size=36
            ),
            MenuButton(
                button_x, start_y + gap,
                button_width, button_height,
                "设置",
                callback=self.on_settings,
                font_size=36
            ),
            MenuButton(
                button_x, start_y + gap * 2,
                button_width, button_height,
                "保存游戏",
                callback=self.on_save,
                font_size=36
            ),
            MenuButton(
                button_x, start_y + gap * 3,
                button_width, button_height,
                "返回主菜单",
                callback=self.on_main_menu,
                font_size=36
            ),
        ]

        self.load_fonts()

    def on_resume(self):
        """继续游戏"""
        self.screen_manager.go_back()

    def on_settings(self):
        """打开设置"""
        self.screen_manager.switch_to(ScreenType.SETTINGS)

    def on_save(self):
        """保存游戏"""
        # 快速保存到当前槽位
        current_slot = self.screen_manager.global_state.get('current_save_slot')
        if current_slot:
            self.save_game(current_slot)
        else:
            # 没有当前存档，需要选择槽位
            self.screen_manager.switch_to(ScreenType.SAVE_LOAD_DIALOG, mode='save')

    def save_game(self, slot: int):
        """保存游戏到指定槽位"""
        import json
        from datetime import datetime

        save_data = {
            'slot': slot,
            'save_time': datetime.now().strftime('%Y-%m-%d %H:%M'),
            'game_day': 1,  # TODO: 从游戏状态获取
            'game_state': {},  # TODO: 保存实际游戏状态
        }

        os.makedirs('data/saves', exist_ok=True)
        save_path = f'data/saves/save_{slot}.json'

        try:
            with open(save_path, 'w', encoding='utf-8') as f:
                json.dump(save_data, f, indent=2, ensure_ascii=False)
            print(f"游戏已保存到槽位 {slot}")
            # TODO: 显示保存成功提示
        except Exception as e:
            print(f"保存失败: {e}")
            # TODO: 显示错误提示

    def on_main_menu(self):
        """返回主菜单"""
        # TODO: 如果有未保存的更改，显示确认对话框
        self.screen_manager.switch_to(ScreenType.INITIAL_MENU)

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.overlay_alpha = 0.0
        self.menu_y_offset = -50
        self.setup_ui()

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

        # 淡入效果
        if self.overlay_alpha < 0.7:
            self.overlay_alpha = min(0.7, self.overlay_alpha + dt * 3)

        # 菜单滑入效果
        if self.menu_y_offset < 0:
            self.menu_y_offset = min(0, self.menu_y_offset + dt * 200)

        for button in self.buttons:
            button.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if not self.active:
            return False

        # 处理按钮事件
        for button in self.buttons:
            if button.handle_event(event):
                return True

        # ESC关闭菜单
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                self.on_resume()
                return True

        return False

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        # 绘制半透明遮罩
        overlay = pygame.Surface(screen.get_size())
        overlay.fill((0, 0, 0))
        overlay.set_alpha(int(self.overlay_alpha * 255))
        screen.blit(overlay, (0, 0))

        width, height = screen.get_size()

        # 渲染标题
        if 'subtitle' in self.fonts:
            title = self.fonts['subtitle'].render("游戏菜单", True, (220, 230, 255))
            title_rect = title.get_rect(center=(width // 2, 80 + self.menu_y_offset))
            screen.blit(title, title_rect)

        # 渲染按钮（带滑入动画）
        for button in self.buttons:
            original_y = button.rect.y
            button.rect.y = int(original_y + self.menu_y_offset)
            button.render(screen)
            button.rect.y = original_y


class SaveLoadDialog(Screen):
    """存档/读档对话框"""

    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.mode = 'load'  # 'save' 或 'load'
        self.save_slots: List = []
        self.selected_slot: Optional[int] = None
        self.setup_ui()

    def setup_ui(self):
        """设置UI"""
        # TODO: 实现存档对话框UI
        pass

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面"""
        super().on_enter(previous_screen, **kwargs)
        self.mode = kwargs.get('mode', 'load')
        # TODO: 加载存档列表

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        # TODO: 实现渲染
        screen.fill((20, 20, 30))
