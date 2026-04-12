"""三体模拟经营游戏 - 主程序入口"""
import os
import pygame
import yaml
import sys
import numpy as np
from pathlib import Path

# 游戏模块
from game.simulator import GameSimulator
from render.camera import Camera
from render.scene import SceneRenderer
from render.ui import create_hud, update_hud, Button, UIManager, get_font, Panel, Label

# UI模块 - 新的界面管理系统
from ui import ScreenManager, InitialMenu, StartGameMenu, SettingsScreen, GameMenu
from ui.screen_manager import ScreenType


# 屏幕模式（保留用于兼容性）
SCREEN_MODE_MAIN = "main"  # 2D主界面
SCREEN_MODE_STARMAP = "starmap"  # 3D星图


def load_config(config_path: str = "config.yaml") -> dict:
    """加载配置文件"""
    config_file = Path(__file__).parent / config_path
    with open(config_file, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def handle_input_starmap(events, camera, simulator, ui_manager):
    """处理3D星图输入"""
    keys = pygame.key.get_pressed()

    for event in events:
        # 退出
        if event.type == pygame.QUIT:
            return False, "quit"

        # 鼠标拖拽旋转视角
        if event.type == pygame.MOUSEMOTION and pygame.mouse.get_pressed()[0]:
            camera.rotate(event.rel[0], event.rel[1])

        # 滚轮缩放
        if event.type == pygame.MOUSEWHEEL:
            camera.zoom(event.y)

        # UI事件
        ui_manager.handle_event(event)

        # 键盘控制
        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                # 返回主界面
                return True, "switch_main"
            elif event.key == pygame.K_SPACE:
                simulator.toggle_pause()
            elif event.key == pygame.K_1:
                camera.zoom(20)
            elif event.key == pygame.K_2:
                camera.zoom(-20)

    # 持续按键移动
    if keys[pygame.K_w] or keys[pygame.K_UP]:
        camera.move(forward=camera.speed)
    if keys[pygame.K_s] or keys[pygame.K_DOWN]:
        camera.move(forward=-camera.speed)
    if keys[pygame.K_a] or keys[pygame.K_LEFT]:
        camera.move(right=-camera.speed)
    if keys[pygame.K_d] or keys[pygame.K_RIGHT]:
        camera.move(right=camera.speed)
    if keys[pygame.K_q]:
        camera.move(up=camera.speed)
    if keys[pygame.K_e]:
        camera.move(up=-camera.speed)

    return True, "starmap"


def render_main_screen(screen: pygame.Surface, simulator: GameSimulator, width: int, height: int):
    """渲染2D主界面"""
    # 背景
    screen.fill((5, 5, 15))

    # 绘制简单的星空背景装饰
    import random
    for _ in range(100):
        x = random.randint(0, width)
        y = random.randint(0, height)
        brightness = random.randint(50, 150)
        pygame.draw.circle(screen, (brightness, brightness, brightness), (x, y), 1)

    # 标题 - 根据窗口大小调整
    title_size = max(36, min(72, width // 15))
    font_title = get_font(title_size)
    title_surf = font_title.render("三体文明", True, (200, 220, 255))
    title_rect = title_surf.get_rect(center=(width // 2, height * 0.1))
    screen.blit(title_surf, title_rect)

    # 获取游戏状态
    state = simulator.get_state()
    entities = state.get("entities", {})
    env_params = state.get("environment", {}).get("params", {})

    # 计算面板尺寸（根据窗口大小）
    panel_width = max(200, min(300, width // 4))
    panel_height = max(200, min(350, height // 2))
    panel_x = width * 0.05
    panel_y = height * 0.2
    gap = (width - panel_x * 2 - panel_width * 3) / 4

    # 左侧面板 - 资源
    panel_resources = Panel(int(panel_x), int(panel_y), int(panel_width), int(panel_height), "资源")
    panel_resources.render(screen)

    resources = entities.get("resources", {})
    label_size = max(18, min(24, width // 50))
    y_offset = 45
    for name, amount in resources.items():
        label = Label(int(panel_x + 10), int(panel_y + y_offset), f"{name}: {int(amount)}", label_size, (180, 200, 220))
        label.render(screen)
        y_offset += int(panel_height / 8)

    # 中间面板 - 文明状态
    panel_mid_x = panel_x + panel_width + gap
    panel_civilization = Panel(int(panel_mid_x), int(panel_y), int(panel_width), int(panel_height), "文明状态")
    panel_civilization.render(screen)

    y_offset = 45
    items = [
        f"人口: {entities.get('people_count', 0)}",
        f"建筑: {entities.get('buildings_count', 0)}",
        f"平均效率: {entities.get('avg_efficiency', 0):.2f}",
        "",
        f"光照强度: {env_params.get('light_intensity', 0):.2f}",
        f"热量水平: {env_params.get('heat_level', 0):.2f}",
        f"稳定性: {env_params.get('stability', 0):.2f}",
        "",
        f"游戏时间: {state.get('time', 0):.1f}"
    ]
    for item in items:
        label = Label(int(panel_mid_x + 10), int(panel_y + y_offset), item, label_size, (180, 200, 220))
        label.render(screen)
        y_offset += int(panel_height / 12)

    # 右侧面板 - 行动
    panel_right_x = panel_x + (panel_width + gap) * 2
    panel_actions = Panel(int(panel_right_x), int(panel_y), int(panel_width), int(panel_height), "行动")
    panel_actions.render(screen)

    # 显示操作提示
    y_offset = 45
    action_items = [
        "查看星图",
        "建造建筑",
        "分配人员",
        "科技研究",
        "外交关系"
    ]
    for item in action_items:
        label = Label(int(panel_right_x + 10), int(panel_y + y_offset), f"▶ {item}", label_size, (150, 180, 220))
        label.render(screen)
        y_offset += int(panel_height / 8)

    # 底部提示
    font_tip = get_font(max(14, min(20, width // 60)))
    tip_surf = font_tip.render("点击右上角按钮进入星图 | ESC 返回主界面", True, (100, 120, 150))
    tip_rect = tip_surf.get_rect(center=(width // 2, height - 30))
    screen.blit(tip_surf, tip_rect)


def handle_input_main(events, simulator, width, height):
    """处理2D主界面输入"""
    for event in events:
        if event.type == pygame.QUIT:
            return False, "quit"

        if event.type == pygame.MOUSEBUTTONDOWN:
            mouse_x, mouse_y = event.pos

            # 检查是否点击了右上角星图按钮区域
            if width - 160 <= mouse_x <= width - 10 and 10 <= mouse_y <= 60:
                return True, "switch_starmap"

            # 检查是否点击了"查看星图"选项（右侧面板）
            if width - 300 <= mouse_x <= width - 50 and 195 <= mouse_y <= 235:
                return True, "switch_starmap"

        if event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                return False, "quit"
            elif event.key == pygame.K_RETURN or event.key == pygame.K_SPACE:
                # 按回车或空格也可以进入星图
                return True, "switch_starmap"

    return True, "main"


def init_screen_manager(screen: pygame.Surface) -> ScreenManager:
    """初始化界面管理器并注册所有界面"""
    manager = ScreenManager()

    # 注册初始菜单
    initial_menu = InitialMenu(manager, screen)
    manager.register_screen(ScreenType.INITIAL_MENU, initial_menu)

    # 注册开始游戏菜单
    start_game_menu = StartGameMenu(manager, screen)
    manager.register_screen(ScreenType.START_GAME_MENU, start_game_menu)

    # 注册设置界面
    settings_screen = SettingsScreen(manager, screen)
    manager.register_screen(ScreenType.SETTINGS, settings_screen)

    # 注册游戏内菜单
    game_menu = GameMenu(manager, screen)
    manager.register_screen(ScreenType.GAME_MENU, game_menu)

    # TODO: 注册主游戏界面和星图界面（需要适配现有代码）

    return manager


def run_game_loop(config: dict, screen_manager: ScreenManager, screen: pygame.Surface):
    """运行游戏主循环"""
    # 创建时钟
    fps = config.get("game", {}).get("fps", 60)
    clock = pygame.time.Clock()

    # 创建游戏模拟器
    simulator = GameSimulator()

    # 设置初始暂停状态
    sim_config = config.get("simulation", {})
    if sim_config.get("initial_paused", False):
        simulator.paused = True

    # 创建摄像机（用于星图）
    camera_config = config.get("camera", {})
    camera = Camera(
        position=(0, 0, -camera_config.get("default_distance", 500)),
        fov=camera_config.get("fov", 500)
    )
    camera.speed = camera_config.get("move_speed", 5)

    # 创建场景渲染器
    scene = SceneRenderer(screen, camera)

    # 创建UI管理器
    state = simulator.get_state()
    ui_manager = create_hud(state, *screen.get_size(), camera)

    # 运行主循环
    running = True
    while running:
        dt = clock.tick(fps) / 1000.0

        # 更新界面管理器
        screen_manager.update(dt)

        # 处理事件
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            else:
                # 先让界面管理器处理事件
                if not screen_manager.handle_event(event):
                    # 如果界面没有处理，进行游戏事件处理
                    pass

        # 渲染
        screen.fill((10, 10, 20))
        screen_manager.render(screen)

        pygame.display.flip()

    pygame.quit()


def main():
    # 加载配置
    config = load_config()

    # Pygame初始化
    pygame.init()

    # 创建窗口
    game_config = config.get("game", {})
    title = game_config.get("title", "三体文明")
    resolution = tuple(game_config.get("resolution", [1280, 720]))
    fullscreen = game_config.get("fullscreen", False)
    resizable = game_config.get("resizable", True)

    # 设置显示模式
    flags = 0
    if fullscreen:
        flags |= pygame.FULLSCREEN
    if resizable:
        flags |= pygame.RESIZABLE

    screen = pygame.display.set_mode(resolution, flags)
    pygame.display.set_caption(title)

    # 窗口居中（仅非全屏时有效）
    if game_config.get("center", True) and not fullscreen:
        display_info = pygame.display.Info()
        display_width = display_info.current_w
        display_height = display_info.current_h
        x = (display_width - resolution[0]) // 2
        y = (display_height - resolution[1]) // 2
        os.environ['SDL_VIDEO_WINDOW_POS'] = f'{x},{y}'
        pygame.display.set_mode(resolution, flags)

    # 初始化界面管理器
    screen_manager = init_screen_manager(screen)

    # 切换到初始菜单
    screen_manager.switch_to(ScreenType.INITIAL_MENU)

    # 运行游戏主循环
    run_game_loop(config, screen_manager, screen)


if __name__ == "__main__":
    main()
    running = True
    while running:
        # 计算delta time
        dt = clock.tick(fps) / 1000.0  # 转换为秒

        # 始终更新模拟器（两个界面都运行）
        if not simulator.paused:
            simulator.update(dt)

        # 获取当前状态
        state = simulator.get_state()

        # 检测窗口大小变化（两种模式都检测）
        new_screen_size = screen.get_size()
        if new_screen_size != current_screen_size:
            current_screen_size = new_screen_size

        # 根据模式处理输入
        if current_mode == SCREEN_MODE_MAIN:
            # 2D主界面模式
            running, next_mode = handle_input_main(
                pygame.event.get(), simulator, current_screen_size[0], current_screen_size[1]
            )

            # 渲染2D主界面
            render_main_screen(screen, simulator, *current_screen_size)

            # 绘制右上角星图按钮
            _draw_starmap_button(screen, current_screen_size[0], current_screen_size[1])

        else:
            # 3D星图模式
            running, next_mode = handle_input_starmap(
                pygame.event.get(), camera, simulator, ui_manager
            )

            # 窗口大小变化时重新创建UI
            if new_screen_size != current_screen_size:
                # 重新创建UI以适应新窗口大小
                ui_manager = create_hud(state, *current_screen_size, camera)

            if not game_over:
                # 碰撞检测
                if camera.check_collision(state["environment"]["stars"]):
                    game_over = True

            # 更新UI数据
            update_hud(ui_manager, simulator.get_state(), camera)

            # 渲染3D星图
            scene.clear(tuple(config.get("colors", {}).get("background", [10, 10, 20])))
            scene.render(simulator.get_state())
            ui_manager.render(screen)

            # 游戏结束画面最后渲染（在最上层）
            if game_over:
                scene.render_game_over(screen)

        # 切换模式
        if next_mode == "switch_starmap":
            current_mode = SCREEN_MODE_STARMAP
            # 重置摄像机位置（复用camera对象）
            camera.position = np.array([0, 0, -camera_config.get("default_distance", 500)])
            camera.rotation = [0, 0]
            camera.fov = camera_config.get("fov", 500)
            camera.speed = camera_config.get("move_speed", 5)
            # 更新scene的camera引用
            scene.camera = camera
            # 重新创建UI
            ui_manager = create_hud(state, *current_screen_size, camera)
        elif next_mode == "switch_main":
            current_mode = SCREEN_MODE_MAIN

        # 翻转显示
        pygame.display.flip()

    pygame.quit()
    sys.exit()


def _draw_starmap_button(screen: pygame.Surface, width: int, height: int):
    """绘制右上角星图按钮"""
    # 按钮区域
    btn_x = width - 160
    btn_y = 10
    btn_w = 150
    btn_h = 50

    # 按钮背景
    btn_rect = pygame.Rect(btn_x, btn_y, btn_w, btn_h)

    # 检测鼠标悬停
    mouse_pos = pygame.mouse.get_pos()
    is_hovered = btn_rect.collidepoint(mouse_pos)

    # 颜色
    if is_hovered:
        bg_color = (60, 80, 120)
    else:
        bg_color = (40, 60, 100)

    # 绘制按钮
    pygame.draw.rect(screen, bg_color, btn_rect, border_radius=8)
    pygame.draw.rect(screen, (100, 130, 180), btn_rect, 2, border_radius=8)

    # 文字
    font = get_font(28)
    text_surf = font.render("星图", True, (200, 220, 255))
    text_rect = text_surf.get_rect(center=btn_rect.center)
    screen.blit(text_surf, text_rect)


if __name__ == "__main__":
    main()