# Phase 12 — Tower Attack MVP（塔自动攻击）

> 目标：让已放置的塔自动攻击范围内的敌人。server-authoritative、最小可行、不持久化。
> 不含：升级 / 出售 / 选塔 UI / 多塔类型 / 商店 / 抽卡 / Boss / 大型 VFX。

## 攻击循环

```
TowerService 单个共享 Heartbeat（驱动所有塔）
  对每座塔：若 (now - lastAttack) ≥ attackInterval：
    → nearestEnemyInRange(塔位, range)  -- 范围内最近的存活敌人（水平距离）
        有目标 → lastAttack = now
                 → flashBeam(塔, 目标)           -- 极简光束反馈（0.08s）
                 → EnemyService.DamageEnemy(目标, damage)
                     致命一击（返回 true）→ onEnemyKilled(ownerPlayer, 目标)
        无目标 → 空闲
ServerInit.onEnemyKilled（与宠物击杀共用）→ RewardService.GiveReward + pushData
```

## 目标选择

- 仅锁定 `EnemyService.GetAliveEnemies()` 中的**存活**敌人；不打逃逸/死亡敌人。
- 取**范围内最近**敌人（水平 XZ 距离 ≤ `range`）。
- 范围内无敌人 → 塔空闲。

## 伤害 / 奖励（不重复）

- 复用既有 `EnemyService.DamageEnemy(enemy, amount)`。
- **击杀只结算一次**：`DamageEnemy` 的 `alive` 一次性守卫——敌人血量归 0 时立即 `alive=false`，
  之后任何来源（宠物/另一座塔）对其 `DamageEnemy` 返回 `false`。
  → **宠物与塔击中同一敌人不会重复发奖**；致命一击者的拥有者获得奖励。
- 塔击杀复用与宠物相同的 `onEnemyKilled` 通道（`ServerInit`）→ 既有奖励 + 反馈，未改 RewardService。
- **逃逸敌人仍不发奖**（逃逸走 `onEscaped` 扣基地血量，与击杀互斥）。

## 战斗参数（TowerConfig.basic_tower）

| 字段 | 值 | 含义 |
|------|----|------|
| `range` | 24 | 攻击范围（studs，水平） |
| `damage` | 8 | 每次攻击伤害 |
| `attackInterval` | 1.0 | 两次攻击间隔（秒） |

缺失时 TowerService 用缺省（24 / 8 / 1.0）。

## 视觉反馈（极简）

- 每次攻击从塔到目标短暂显示一条 Neon 光束（`Part`，`0.08s` 后销毁）。
- 敌人受击仍有既有的命中变色（`DamageEnemy` 内）。
- **无投射物系统、无大型特效。**

## 塔生命周期 / 无残留

- 塔仍**仅当前会话**存在，由 `TowerService` 的 `towers` 数组跟踪。
- 攻击由**单个共享 `RunService.Heartbeat`** 驱动（**非每塔一个循环**）→ 塔/玩家移除后不残留攻击循环。
- 玩家离开：`Players.PlayerRemoving` → `clearPlayerTowers` 销毁其塔模型并从数组移除；
  共享 Heartbeat 自然不再遍历到它们。

## 边界

- **扩展** `TowerService`（+攻击循环 / 目标选择 / 光束）与 `TowerConfig`（攻击参数）。
- **未改动** `CombatService`（宠物战斗）；塔走自己的 Heartbeat，二者独立但共用 `onEnemyKilled`。
- **未改动**受保护文件：`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `TaskConfig.lua`。
- **未改动** `MainUI.client.lua`、`Net.lua`（无新增 remote；塔/光束为服务端世界对象，自动复制）。
- **未改动** DataStore 名称 / `CURRENT_DATA_VERSION`；塔与战斗状态不持久化。

## 范围外

塔升级 / 出售 / 选塔 UI / 多塔类型 / 商店 / 抽卡 / 付费 / Boss / 大型 VFX / 持久化塔。

## 已知限制

- 目标选择为"最近"，无优先级（最前/最血/最近基地等）。
- 范围用水平 XZ 距离；地形高差可能略有出入。
- 光束为短暂 Part，非持续/平滑投射物。
- 单一塔类型（`basic_tower`）。

> 塔放置见 [`Phase11-TowerPlacement.md`](Phase11-TowerPlacement.md) / [`Phase11_5-TowerPlacementUX.md`](Phase11_5-TowerPlacementUX.md)；
> 宠物战斗见 [`Phase8-CombatLoop.md`](Phase8-CombatLoop.md)；总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
