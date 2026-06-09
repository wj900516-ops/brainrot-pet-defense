# Phase 13 — Run Restart / Session Reset MVP

> 目标：基地被摧毁（失败）后，玩家可重开本局。server-authoritative、无大型 UI、不持久化。
> 不含：塔退款 / 升级 / 出售 / 新塔/敌人 / Boss / 商店 / 抽卡 / 难度曲线。

## 流程

```
基地 HP 归 0 → WaveService 失败 → onSessionFailed → ServerInit 广播 SessionState{failed=true}
  → RunControl 客户端显示 "BASE DESTROYED — Press R to Restart"
玩家按 R → RestartRemote:FireServer("Restart")（仅意图）
  → ServerInit 校验 WaveService.IsFailed()：
      未失败（运行中）→ 拒绝 { success=false, reason="run_active" }
      已失败 → TowerService.ClearAll() + WaveService.ResetSession()
              → 广播 SessionState{failed=false} + 回推 Result{success=true}
  → RunControl 隐藏提示 + toast "Run restarted!"
```

## 重开做了什么（server-authoritative）

`WaveService.ResetSession()`（仅失败后允许，否则返回 false）：
- `EnemyService.ClearAll()` —— 清残余敌人（清后 `alive=false`，**不再发奖/扣基地血量**）。
- `baseHp = BASE_MAX_HP`、`waveNumber = 0`、`sessionFailed = false`。
- 刷新基地状态板（回到 `Wave 0 → 即将 Wave 1 / Base HP 满`）。
- `startWaveLoop()` 重新开始刷怪。

`ServerInit` 编排：在 `ResetSession` 之前 `TowerService.ClearAll()` 清除所有塔
（保持 `WaveService` 不依赖 `TowerService`）。

## 防重复波次循环（generation 代号）

- 波次循环带 `generation` 代号；`startWaveLoop()` 每次 `generation += 1` 并启动带新代号的循环。
- 循环在多处检查 `myGen == generation`：一旦代号变化（有新循环启动）或 `sessionFailed`，立即退出。
- 因此**同一时刻至多一个活动波次循环**：重开时旧循环（若残留）因代号变化而退出，新循环接管，**不会重复刷怪**。

## 清理保证

- **敌人**：`EnemyService.ClearAll()` 置 `alive=false` + 销毁模型；清后移动/逃逸/击杀逻辑都不再作用于它们 → 不发奖、不扣基地血量。
- **塔**：`TowerService.ClearAll()` 销毁所有塔模型并清空跟踪数组；塔攻击的**单个共享 Heartbeat** 之后不再遍历到任何塔 → 无残留攻击。
- 玩家离开仍由 `TowerService` 的 `PlayerRemoving → clearPlayerTowers` 清理其塔。

## 校验 / 边界

- 客户端只发 `"Restart"` 意图；**不能**直接设置波次/基地血量/金币/敌人状态。
- 仅**失败后**允许重开；运行中请求被拒（`run_active`）。
- **金币不重置**（玩家保留金币）；**塔被清除且不退款**（见已知限制）。
- **未持久化** 任何 run 状态。

## 网络

- 新增 **`RestartRemote`**（RemoteEvent，经 `Net.RestartRemote()`，与既有 remote 同模式）：
  - C→S `"Restart"`（仅意图）
  - S→C `"Result", { success, reason }`（`reason`：`restarted` / `run_active` / `failed`）
  - S→C `"SessionState", { failed }`（失败/重开时广播；玩家加入时单发）→ 客户端显示/隐藏提示

## 文件 / 保护边界

- **扩展** `WaveService`（generation 循环 + `ResetSession` + `onSessionFailed`）、`TowerService`（`ClearAll`）、`ServerInit`（restart 接线）、`Net.lua`（+RestartRemote）。
- **新增** `StarterGui/RunControl/RunControl.client.lua`（R 键 + 提示 + toast）。
- `EnemyService.ClearAll()` 复用 Phase 9，未改 EnemyService。
- **未改动** `MainUI.client.lua`、受保护文件（`DummyTargetService`/`GameEventService`/`TaskService`/`RewardService`/`TaskConfig.lua`）、`CombatService`。
- **未改动** DataStore 名称 / `CURRENT_DATA_VERSION`；run 状态不持久化。

## 范围外

塔退款 / 升级 / 出售 / 新塔 / 新敌人 / Boss / 商店 / 抽卡 / 付费 / 大型 UI / 难度曲线 / 持久化 run 状态。

## 已知限制

- 重开**清除已放置的塔且不退款**（金币已花，塔消失）——属本阶段范围；后续可加退款/持久化。
- 仅失败后可重开（运行中拒绝），无"放弃当前局"主动重开。
- 重开提示/反馈在独立 ScreenGui（非 MainUI）。
- 金币不重置（玩家保留累计金币）。

> 波次/基地见 [`Phase9-WaveBaseHP.md`](Phase9-WaveBaseHP.md)；塔见 [`Phase11-TowerPlacement.md`](Phase11-TowerPlacement.md) / [`Phase12-TowerAttack.md`](Phase12-TowerAttack.md)；总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
