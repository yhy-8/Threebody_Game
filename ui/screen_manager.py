"""界面管理器 - 管理所有游戏界面的切换和状态"""

import pygame
from typing import Dict, Optional, Any, Callable
from enum import Enum, auto


class ScreenType(Enum):
    """界面类型枚举"""
    INITIAL_MENU = auto()      # 初始菜单
    START_GAME_MENU = auto()   # 开始游戏菜单
    SETTINGS = auto()          # 设置界面
    GAME_MENU = auto()         # 游戏内菜单
    MAIN_SCREEN = auto()       # 2D主游戏界面
    STARMAP_VIEW = auto()      # 3D星图界面
    SAVE_LOAD_DIALOG = auto()  # 存档对话框


class Screen:
    """界面基类"""

    def __init__(self, screen_manager: 'ScreenManager', screen: pygame.Surface):
        self.screen_manager = screen_manager
        self.screen = screen
        self.rect = screen.get_rect()
        self.fonts: Dict[str, pygame.font.Font] = {}
        self.visible = True
        self.active = False
        self.background_color = (10, 10, 20)

        # 动画相关
        self.animation_progress = 0.0
        self.animation_speed = 5.0
        self.is_animating_in = False
        self.is_animating_out = False

    def load_fonts(self):
        """加载界面所需字体"""
        from render.ui import get_font

        self.fonts = {
            'title': get_font(72),
            'subtitle': get_font(48),
            'normal': get_font(28),
            'small': get_font(20),
            'tiny': get_font(14),
        }

    def on_enter(self, previous_screen: Optional[ScreenType] = None, **kwargs):
        """进入界面时调用"""
        self.active = True
        self.visible = True
        self.is_animating_in = True
        self.is_animating_out = False
        self.animation_progress = 0.0

    def on_exit(self):
        """退出界面时调用"""
        self.is_animating_out = True
        self.is_animating_in = False

    def finish_exit(self):
        """完成退出动画后调用"""
        self.active = False
        self.visible = False
        self.is_animating_out = False
        self.is_animating_in = False

    def update(self, dt: float):
        """更新界面状态"""
        # 处理进入动画
        if self.is_animating_in:
            self.animation_progress += dt * self.animation_speed
            if self.animation_progress >= 1.0:
                self.animation_progress = 1.0
                self.is_animating_in = False

        # 处理退出动画 - 注意：当屏幕不在当前时，直接完成退出
        if self.is_animating_out:
            # 如果已经不再是当前屏幕，直接完成退出
            if not self.active and not self.visible:
                self.finish_exit()
                return

            self.animation_progress -= dt * self.animation_speed
            if self.animation_progress <= 0.0:
                self.animation_progress = 0.0
                self.finish_exit()

    def setup_ui(self):
        """设置UI - 子类可重写此方法"""
        pass

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理输入事件，返回是否处理了事件"""
        return False

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return

        # 清屏
        screen.fill(self.background_color)

        # 应用动画效果
        if self.animation_progress < 1.0:
            # 淡入效果
            alpha = int(255 * self.animation_progress)
            # 这里可以添加更多动画效果

    def get_animation_offset(self) -> tuple:
        """获取动画偏移量"""
        if self.is_animating_in:
            offset = (1.0 - self.animation_progress) * 50
            return (0, int(offset))
        elif self.is_animating_out:
            offset = (1.0 - self.animation_progress) * 50
            return (0, -int(offset))
        return (0, 0)


class ScreenManager:
    """界面管理器 - 单例模式"""

    _instance = None

    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if self._initialized:
            return

        self._initialized = True
        self.screens: Dict[ScreenType, Screen] = {}
        self.current_screen: Optional[Screen] = None
        self.previous_screen_type: Optional[ScreenType] = None
        self.current_screen_type: Optional[ScreenType] = None
        self.screen_stack: list = []  # 界面栈，用于返回功能
        self.transition_callbacks: list = []  # 切换回调

        # 全局状态
        self.global_state = {
            'game_started': False,
            'current_save_slot': None,
            'settings': {},
        }

    def register_screen(self, screen_type: ScreenType, screen: Screen):
        """注册界面"""
        self.screens[screen_type] = screen

    def switch_to(self, screen_type: ScreenType, push_to_stack: bool = True, **kwargs):
        """切换到指定界面"""
        if screen_type not in self.screens:
            print(f"错误：界面 {screen_type} 未注册")
            return

        # 如果当前已经是目标界面，不做任何操作
        if self.current_screen_type == screen_type:
            return

        new_screen = self.screens[screen_type]

        # 先退出当前界面
        if self.current_screen:
            # 保存当前界面到栈（在退出前保存）
            if push_to_stack and self.current_screen_type:
                self.screen_stack.append(self.current_screen_type)
            self.current_screen.on_exit()

        # 更新状态
        self.previous_screen_type = self.current_screen_type
        self.current_screen_type = screen_type
        self.current_screen = new_screen

        # 进入新界面
        self.current_screen.on_enter(self.previous_screen_type, **kwargs)

        # 触发回调
        for callback in self.transition_callbacks:
            callback(screen_type, self.previous_screen_type)

    def go_back(self, fallback_screen: Optional[ScreenType] = None):
        """返回上级界面"""
        # 先清空当前界面的退出动画状态，确保能正确切换
        if self.current_screen:
            self.current_screen.is_animating_out = False
            self.current_screen.animation_progress = 1.0

        if self.screen_stack:
            previous = self.screen_stack.pop()
            self.switch_to(previous, push_to_stack=False)
        elif fallback_screen:
            self.switch_to(fallback_screen, push_to_stack=False)
        else:
            # 如果没有fallback，尝试回到初始菜单
            try:
                self.switch_to(ScreenType.INITIAL_MENU, push_to_stack=False)
            except:
                # 如果连初始菜单都没有，不做任何操作
                pass

    def clear_stack_and_switch(self, screen_type: ScreenType, **kwargs):
        """清空栈并切换到指定界面
        用于从游戏内退出到主菜单时，确保清理完整的状态
        """
        # 清空栈
        self.screen_stack.clear()
        # 切换到目标界面，不推入栈
        self.switch_to(screen_type, push_to_stack=False, **kwargs)

    def update(self, dt: float):
        """更新当前界面"""
        if self.current_screen:
            self.current_screen.update(dt)

    def handle_event(self, event: pygame.event.Event) -> bool:
        """处理事件"""
        if self.current_screen:
            return self.current_screen.handle_event(event)
        return False

    def render(self, screen: pygame.Surface):
        """渲染当前界面"""
        if self.current_screen:
            self.current_screen.render(screen)

    def on_transition(self, callback: Callable):
        """注册界面切换回调"""
        self.transition_callbacks.append(callback)

    def get_screen(self, screen_type: ScreenType) -> Optional[Screen]:
        """获取指定界面"""
        return self.screens.get(screen_type)

    def is_current(self, screen_type: ScreenType) -> bool:
        """检查是否当前界面"""
        return self.current_screen_type == screen_type
