# Phase 10 — Route-Based Enemy Movement / Map Pathing MVP

> 目标：让敌人沿真实路径（航点 waypoints）移动；在路径起点生成，路径终点即基地。
> 仅实现路径移动。**不**实现建塔/重开/商店等。简单、确定性、server-authoritative、不持久化。

## 路径（route）

- 优先使用 **`Workspace.EnemyPath`** 文件夹下的航点部件：`Waypoint_01` / `Waypoint_02` / ...（人工在 Studio 摆放）。
  - 按**名称排序**确定顺序；需 **≥ 2 个** 才算有效。
  - 航点可见性由摆放者决定（建议摆成沿路面的标记）。
- **缺失/不足时兜底**：`EnemyService` 自动在 `Workspace.EnemyPath` 下生成一条**内置直线**路径
  （`FALLBACK_SPAWN (0,3,-40)` → `FALLBACK_BASE (0,3,0)`，5 个航点），
  代码生成的兜底航点为**不可见**（`Transparency = 1`，调试用）。
- 路径解析 **memoized**：仅在首次需要时解析一次（`resolveRoute()`）。

## 敌人生成

- 敌人在 **路径第一个航点**（route[1]）生成，`targetIndex = 2`（朝第二个航点前进）。
- **不会**在地图中间生成（除非人工把首航点放在中间）。
- `LagBlob` 敌人类型与数值**未改动**。

## 敌人移动

- 每帧朝当前目标航点 `route[targetIndex]` 直线移动（无 PathfindingService、无复杂寻路）。
- 距目标航点 ≤ `REACH_WAYPOINT_DISTANCE (3)` → 前进到下一个航点。
- 到达**最后一个航点**（基地）→ 视为**逃逸**：触发 Phase 9 的 `onEscaped` → 基地扣血。
- **逃逸不发奖励**；**击杀仍只发一次奖励**（沿用 Phase 8/8.5/9 行为，未改动）。

## 基地位置

- `EnemyService.GetBasePosition()` 返回路径最后一个航点。
- `WaveService` 把**基地状态板**（世界 Billboard）放在该终点附近，显示
  `Wave N | Base HP X/10`，失败时红字 `BASE DESTROYED — reached Wave N`。
- Base HP 行为（逃逸 -1、归 0 失败、失败停刷怪 + ClearAll）**完全不变**。

## 波次兼容性（未变）

有限波次 / 本波全部解决后下一波 / 逃逸扣基地血量 / Base HP=0 失败 / 失败后停止刷怪 —— 均沿用 Phase 9，行为不变。

## 架构 / 边界

- **扩展** `EnemyService`（路径解析 + 航点移动 + `GetBasePosition`）与 `WaveService`（基地板定位到路径终点）。
- `CombatService` **未改动**（仍按敌人 `model.Position` 做范围判定，与航点移动天然兼容）。
- **未改动**受保护文件：`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `TaskConfig.lua`。
- **未改动** `MainUI.client.lua`、`Net.lua`；无新增客户端变更 remote；server-authoritative。
- **未改动** DataStore：`PlayerData_v1` / `CURRENT_DATA_VERSION = 2`；路径/波次状态**不持久化**。

## 可调参数（EnemyService 顶部）

| 参数 | 默认 | 含义 |
|------|------|------|
| `PATH_FOLDER_NAME` | `"EnemyPath"` | Workspace 路径文件夹名 |
| `WAYPOINT_PREFIX` | `"Waypoint_"` | 航点部件名前缀 |
| `FALLBACK_SPAWN` | (0,3,-40) | 兜底路径起点 |
| `FALLBACK_BASE` | (0,3,0) | 兜底路径终点（基地） |
| `FALLBACK_SEGMENTS` | 4 | 兜底直线分段（5 个航点） |
| `REACH_WAYPOINT_DISTANCE` | 3 | 到达航点的判定距离 |

## 范围外（Out of Scope）

建塔 / 重开按钮·按键 / 商店 / 抽卡 / Boss / 新敌人 / 付费 / 大型 UI 重设计 / 路径或波次持久化。

## 已知限制

- 兜底路径为直线；要真实"沿路面拐弯"，请在 Studio 的 `Workspace.EnemyPath` 摆放 `Waypoint_01..N`。
- `Workspace` 未纳入 Rojo 映射，因此人工摆放的 `EnemyPath` 不会被 Rojo 覆盖；代码兜底确保无 EnemyPath 也能跑。
- 航点判定为"接近即切换"，转角可能略有内切（MVP 可接受）。
- 仍无重开按钮：失败后重新 Play Solo 开新会话。

> 波次/基地见 [`Phase9-WaveBaseHP.md`](Phase9-WaveBaseHP.md)；战斗见 [`Phase8-CombatLoop.md`](Phase8-CombatLoop.md)；总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
