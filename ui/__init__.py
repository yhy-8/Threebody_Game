"""UI模块 - 游戏界面系统

包含所有游戏界面：
- InitialMenu: 初始菜单
- StartGameMenu: 开始游戏菜单
- SettingsScreen: 设置界面
- GameMenu: 游戏内菜单
- MainScreen: 2D主游戏界面
- StarmapView: 3D星图界面
- TechTreeScreen: 科技树界面
- DecisionScreen: 决策界面（建筑建造与政策）
- ZoneViewScreen: 区域浏览界面
"""

from .screen_manager import ScreenManager, Screen
from .initial_menu import InitialMenu
from .start_game_menu import StartGameMenu
from .settings_screen import SettingsScreen
from .game_menu import GameMenu
from .main_screen import MainScreen
from .starmap_view import StarmapView
from .tech_tree_screen import TechTreeScreen
from .decision_screen import DecisionScreen
from .zone_view_screen import ZoneViewScreen
from .population_screen import PopulationScreen

__all__ = [
    'ScreenManager',
    'Screen',
    'InitialMenu',
    'StartGameMenu',
    'SettingsScreen',
    'GameMenu',
    'MainScreen',
    'StarmapView',
    'TechTreeScreen',
    'DecisionScreen',
    'ZoneViewScreen',
    'PopulationScreen',
]