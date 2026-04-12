# 三体游戏界面架构设计

## 1. 界面层级结构

```
┌─────────────────────────────────────────────────────────────┐
│                        GAME_ROOT                           │
│                  （游戏状态管理器）                          │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌──────────────────┐    ┌───────────────┐
│  INITIAL_MENU │     │   GAME_SCREEN    │    │   DIALOG_BOX  │
│   初始菜单界面 │     │     游戏界面      │    │   模态对话框   │
└───────────────┘     └──────────────────┘    └───────────────┘
                              │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌───────────────┐     ┌──────────────────┐    ┌───────────────┐
│  MAIN_SCREEN  │     │   STARMAP_VIEW   │    │   SUB_PANELS  │
│   2D主界面    │     │    3D星图视图     │    │   各种子面板   │
└───────────────┘     └──────────────────┘    └───────────────┘
```

## 2. 界面定义

### 2.1 初始菜单界面 (InitialMenu)

**功能**：游戏启动后显示的第一个界面

**包含元素**：
- 游戏标题 "三体文明"
- 背景动画（星空/三体运动预览）
- 主菜单按钮：
  - 「开始游戏」→ 进入 StartGameMenu
  - 「设置」→ 进入 SettingsScreen
  - 「退出」→ 退出游戏
- 版本号显示

**交互**：
- 鼠标悬停按钮高亮
- 点击执行对应操作
- ESC键退出游戏

### 2.2 开始游戏菜单 (StartGameMenu)

**功能**：选择新游戏或继续游戏

**包含元素**：
- 标题 "开始游戏"
- 选项按钮：
  - 「新游戏」→ 创建新存档，进入游戏
  - 「继续游戏」→ 加载最近存档，进入游戏
  - 「加载存档」→ 显示存档列表对话框
  - 「返回」→ 返回 InitialMenu
- 存档预览区域（显示最近存档信息）

**交互**：
- 点击选择对应功能
- 新游戏时检查是否有存档，提示覆盖

### 2.3 设置界面 (SettingsScreen)

**功能**：游戏各种设置

**包含标签页**：

**「游戏」标签**：
- 时间流逝速度滑块
- 自动保存间隔
- 教程开关

**「显示」标签**：
- 分辨率选择
- 全屏/窗口模式
- 画质等级
- 粒子效果开关

**「音频」标签**：
- 主音量滑块
- 音乐音量
- 音效音量

**「控制」标签**：
- 鼠标灵敏度
- 键盘快捷键显示

**底部按钮**：
- 「应用」→ 保存设置
- 「重置」→ 恢复默认
- 「返回」→ 返回上级界面

### 2.4 游戏主界面 (MainScreen) - 已有

**保持现有设计**：
- 顶部的标题
- 左侧资源面板
- 中间文明状态面板
- 右侧行动面板
- 右上角星图按钮

**新增元素**：
- 左上角菜单按钮 → 打开游戏菜单
- 底部状态栏显示当前时间/暂停状态

### 2.5 游戏菜单 (GameMenu) - 新增

**功能**：游戏内按ESC或点击菜单按钮打开

**包含选项**：
- 「继续游戏」→ 关闭菜单
- 「设置」→ 打开设置界面
- 「保存游戏」→ 快速保存
- 「加载存档」→ 打开存档列表
- 「返回主菜单」→ 确认后返回
- 「退出游戏」→ 确认后退出

### 2.6 3D星图 (StarmapView) - 已有

**保持现有设计**：
- 3D三体运动可视化
- 摄像机控制
- HUD显示
- ESC返回主界面

## 3. 界面流转图

```
                        ┌─────────────┐
                        │   启动游戏   │
                        └──────┬──────┘
                               │
                               ▼
                ┌──────────────────────────────┐
                │                              │
                ▼                              │
        ┌───────────────┐                      │
        │  InitialMenu │◄─────────────────────┘
        │   初始菜单    │    返回主菜单/退出游戏
        └───────┬───────┘
                │
    ┌───────────┼───────────┐
    │           │           │
    ▼           ▼           ▼
┌────────┐ ┌──────────┐ ┌────────┐
│ 退出游戏 │ │StartGame │ │Settings│
└────────┘ │  Menu    │ │ Screen │
           └────┬─────┘ └────┬───┘
                │            │
    ┌───────────┼───┐        │
    │           │   │        ▼
    ▼           ▼   ▼    ┌────────┐
┌────────┐ ┌───────────┐ │返回上级 │
│  新游戏  │ │ 继续游戏  │ └────────┘
└───┬────┘ └─────┬─────┘
    │            │
    └──────┬─────┘
           │
           ▼
    ┌──────────────────┐
    │                  │
    ▼                  │
┌───────────┐          │
│MainScreen │          │
│  2D主界面  │          │
└─────┬─────┘          │
      │                │
  ┌───┴───┐            │
  │       │            │
  ▼       ▼            │
星图按钮  ESC/菜单      │
  │       │            │
  ▼       ▼            │
┌───────────┐    ┌──────────┐
│StarmapView│    │ GameMenu │
│  3D星图    │    │ 游戏菜单  │
└─────┬─────┘    └────┬─────┘
      │               │
      │         ┌─────┴─────┐
      │         ▼           ▼
      │    继续游戏    设置/保存/加载
      │         │           │
      ▼         ▼           ▼
   ESC返回  关闭菜单    对应功能
      │         │           │
      └─────────┴───────────┘
                  │
                  ▼
         ┌───────────────┐
         │  返回到上级界面 │
         └───────────────┘
```

## 4. 界面间通信机制

### 4.1 游戏状态管理器 (GameStateManager)

```python
class GameStateManager:
    """管理游戏全局状态和界面切换"""

    def __init__(self):
        self.current_screen = None
        self.previous_screen = None
        self.game_data = {}  # 游戏存档数据
        self.settings = {}   # 游戏设置

    def switch_to(self, screen_name: str, **kwargs):
        """切换到指定界面"""
        self.previous_screen = self.current_screen
        self.current_screen = screen_name
        # 触发界面切换事件

    def go_back(self):
        """返回上级界面"""
        if self.previous_screen:
            self.switch_to(self.previous_screen)

    def save_game(self, slot: int = 0):
        """保存游戏"""
        pass

    def load_game(self, slot: int = 0):
        """加载游戏"""
        pass
```

### 4.2 事件系统

```python
# 界面间通信使用事件机制
class UIEvents:
    SWITCH_SCREEN = "switch_screen"      # 切换界面
    GO_BACK = "go_back"                  # 返回上级
    SAVE_GAME = "save_game"              # 保存游戏
    LOAD_GAME = "load_game"              # 加载游戏
    NEW_GAME = "new_game"                # 新游戏
    SETTINGS_CHANGED = "settings_changed" # 设置变更
    GAME_PAUSED = "game_paused"          # 游戏暂停
    GAME_RESUMED = "game_resumed"         # 游戏继续
```

## 5. 待实现功能清单

### 5.1 界面层

- [x] **InitialMenu** - 初始菜单界面
- [x] **StartGameMenu** - 开始游戏菜单
- [x] **SettingsScreen** - 设置界面
- [x] **GameMenu** - 游戏内菜单
- [ ] **MainScreen** - 2D主游戏界面（待整合）
- [ ] **StarmapView** - 3D星图界面（待整合）

### 5.2 对话框系统（简化实现）

**设计理念**：对话框不是独立的界面类型，而是**在当前界面上叠加一个带遮罩的面板**。每个界面自行管理对话框状态。

**实现方式**：

```python
class SomeScreen(Screen):
    def __init__(self, ...):
        ...
        # 对话框状态管理
        self.showing_dialog = False
        self.dialog_type = None  # 'confirm_exit', 'save_success', etc.
        self.dialog_panel = None  # 对话框面板实例
        
    def on_quit_clicked(self):
        """点击退出按钮时显示确认对话框"""
        self.showing_dialog = True
        self.dialog_type = 'confirm_exit'
        self.dialog_panel = ConfirmPanel(
            title="确认退出",
            message="确定要退出游戏吗？",
            on_confirm=self._do_quit,
            on_cancel=self._close_dialog
        )
    
    def _close_dialog(self):
        """关闭对话框"""
        self.showing_dialog = False
        self.dialog_type = None
        self.dialog_panel = None
    
    def handle_event(self, event):
        # 如果显示对话框，优先处理对话框事件
        if self.showing_dialog and self.dialog_panel:
            if self.dialog_panel.handle_event(event):
                return True
        
        # 正常界面事件处理...
        
    def render(self, screen):
        # 先渲染正常界面
        ...
        
        # 如果显示对话框，渲染遮罩和对话框
        if self.showing_dialog and self.dialog_panel:
            # 半透明黑色遮罩
            overlay = pygame.Surface(screen.get_size())
            overlay.fill((0, 0, 0))
            overlay.set_alpha(180)
            screen.blit(overlay, (0, 0))
            
            # 渲染对话框面板
            self.dialog_panel.render(screen)
```

**对话框类型**：

1. **ConfirmPanel** - 确认对话框（是/否）
2. **MessagePanel** - 消息对话框（确定）
3. **InputPanel** - 输入对话框（文本输入）
4. **SaveSlotPanel** - 存档槽位选择（用于存档/读档）

**优点**：
- 无需独立界面类型，减少架构复杂度
- 对话框与当前界面上下文保持关联
- 实现简单，维护方便
- 动画效果易于实现（淡入、缩放等）

### 5.3 功能层

- [x] **ScreenManager** - 界面管理器（单例模式，管理所有界面）
- [x] **SettingsManager** - 设置管理器（内嵌于SettingsScreen，支持JSON序列化）
- [x] **EventSystem** - 事件系统（基于Pygame事件循环）
- [ ] **GameStateManager** - 游戏状态管理器（需进一步整合游戏逻辑）
- [ ] **SaveManager** - 存档管理器（基础功能已集成，需完善完整游戏状态序列化）

### 5.4 整合层（已完成 ✅）

- [x] 主循环与界面系统整合
- [x] 现有MainScreen和StarmapView接入新架构
- [x] 配置系统扩展支持设置保存
- [x] UI联动功能（返回按钮、ESC键、状态保存、游戏暂停）
