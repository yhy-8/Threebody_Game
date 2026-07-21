extends Node
## 全局事件总线 — 解耦 UI 与模拟逻辑

signal screen_changed(screen_name: String)
signal game_started(universe_name: String)
signal game_loaded(universe_name: String)
signal game_paused(paused: bool)
signal time_scale_changed(scale: float)
signal game_over(reason: String)
signal scenario_phase_changed(new_phase: String, transition_day: float)
