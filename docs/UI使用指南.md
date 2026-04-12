# UI系统使用指南

## 架构概览

```
┌─────────────────────────────────────────────────────────────┐
│                        ScreenManager                        │
│                      (单例模式管理器)                        │
└──────────────┬──────────────────────────────────────────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌──────────┐   ┌────────────┐
│ 菜单界面  │   │ 游戏界面    │
└────┬─────┘   └─────┬──────┘
     │               │
  ┌──┴──┐       ┌───┴────┐
  ▼     ▼       ▼        ▼
Initial  Start  Main    Starmap
Menu    Game   Screen   View
       Menu
```

## 界面类型说明

| 界面 | 类型 | 功能 |
|------|------|------|
| **InitialMenu** | 菜单 | 游戏启动后的主菜单（开始游戏、设置、退出） |
| **StartGameMenu** | 菜单 | 新游戏/继续游戏/加载存档选择 |
| **SettingsScreen** | 菜单 | 游戏设置（游戏、显示、音频、控制四个标签页） |
| **GameMenu** | 菜单 | 游戏内ESC菜单（继续、设置、保存、返回主菜单） |
| **MainScreen** | 游戏 | 2D主游戏界面，显示资源、文明状态、行动面板 |
| **StarmapView** | 游戏 | 3D星图界面，显示三体运动，支持摄像机控制 |

## 快速使用指南

### 1. 启动游戏

```python
from main import main
main()
```

### 2. 界面切换

```python
from ui.screen_manager import ScreenType

# 获取屏幕管理器
screen_manager = init_screen_manager(screen)

# 切换到设置界面
screen_manager.switch_to(ScreenType.SETTINGS)

# 返回上级界面
screen_manager.go_back()
```

### 3. 处理事件

```python
# 在主循环中
for event in pygame.event.get():
    if event.type == pygame.QUIT:
        running = False
    else:
        # 让屏幕管理器处理事件
        screen_manager.handle_event(event)
```

### 4. 更新和渲染

```python
# 在主循环中
dt = clock.tick(fps) / 1000.0

# 更新当前界面
screen_manager.update(dt)

# 渲染
screen.fill((10, 10, 20))
screen_manager.render(screen)
pygame.display.flip()
```

## 界面开发指南

### 创建新界面

```python
from ui.screen_manager import Screen, ScreenType

class MyNewScreen(Screen):
    def __init__(self, screen_manager, screen: pygame.Surface):
        super().__init__(screen_manager, screen)
        self.setup_ui()

    def setup_ui(self):
        """设置UI组件"""
        pass

    def on_enter(self, previous_screen=None, **kwargs):
        """进入界面时调用"""
        super().on_enter(previous_screen, **kwargs)

    def update(self, dt: float):
        """更新界面"""
        super().update(dt)

    def handle_event(self, event) -> bool:
        """处理事件，返回是否处理了事件"""
        return super().handle_event(event)

    def render(self, screen: pygame.Surface):
        """渲染界面"""
        if not self.visible:
            return
        screen.fill(self.background_color)
```

### 注册新界面

```python
def init_screen_manager(screen: pygame.Surface) -> ScreenManager:
    manager = ScreenManager()

    # ... 其他界面 ...

    # 注册新界面
    my_screen = MyNewScreen(manager, screen)
    manager.register_screen(ScreenType.MY_NEW_SCREEN, my_screen)

    return manager
```

## 常见问题

### Q: 如何在界面之间传递数据？

**A:** 使用 `switch_to` 的 `**kwargs` 参数：

```python
# 传递数据
screen_manager.switch_to(ScreenType.GAME_MENU, save_slot=3)

# 接收数据
def on_enter(self, previous_screen=None, **kwargs):
    save_slot = kwargs.get('save_slot')
```

### Q: 如何实现界面动画？

**A:** 在 `update` 方法中更新动画状态，在 `render` 中应用：

```python
def update(self, dt: float):
    super().update(dt)
    # 更新动画进度
    self.animation_progress = min(1.0, self.animation_progress + dt * 2)

def render(self, screen: pygame.Surface):
    # 应用动画效果（如淡入）
    alpha = int(255 * self.animation_progress)
    # ... 渲染代码 ...
```

### Q: 如何处理屏幕尺寸变化？

**A:** 在 `on_enter` 中重新设置UI：

```python
def on_enter(self, previous_screen=None, **kwargs):
    super().on_enter(previous_screen, **kwargs)
    # 重新设置UI以适应新窗口大小
    self.setup_ui()
```

---

**更多详细信息请参考：**
- `docs/UI架构设计.md` - 架构设计文档
- `docs/界面系统实现说明.md` - 详细实现说明
- `ui/screen_manager.py` - ScreenManager核心实现
