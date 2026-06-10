# Phase 15 — 玩家 XP / 等级 / 技能点地基（MVP）

> 敌人击杀发放 XP（金币之外），XP 提升玩家等级，每升一级 +1 技能点。
> 技能点会持久保存但**暂不可消费**。本阶段只搭进度地基，**不实现技能树/技能效果**。
> 这是未来"大型玩家技能树 + 宠物技能树"的资源基础。

## 1. Overview（概述）

- 击杀走既有奖励通道 `RewardService.GiveReward(player, { rewardCoins, rewardXP })`（任务完成也共用此路径）。
- 升级与技能点累计集中在 `PlayerDataService.AddXP`（服务端权威）。
- XP 曲线集中在单一 helper `PlayerDataService.GetXPRequiredForLevel(level)`，随等级递增以节流后期产出。
- 持久化 schema 从 **v2 → v3**：新增 `SkillPoints`（`Level`/`XP` 早已存在）。DataStore 名称不变。

## 2. Player Fantasy（玩家体验）

打怪不只是攒金币——每次击杀都在向下一级推进；升级时获得一个技能点并看到 `Level Up! +1 Skill Point`。
点数慢慢攒着，为日后投入技能树做准备。后期升级越来越慢，让点数显得珍贵、不易刷爆。

## 3. Detailed Rules（规则）

- **XP 来源**：敌人击杀（普通/ Boss）。普通怪小额、Boss 更高。**逃逸不发 XP、不发金币**（仍走 `OnEnemyEscaped` 只扣基地血量）。
- **一次性**：`EnemyService.DamageEnemy` 的 `alive` 守卫保证每个敌人只结算一次击杀 → XP/金币不重复（宠物与塔击同一目标也只发一次）。
- **统一路径**：宠物击杀与塔击杀都经 `ServerInit.onEnemyKilled` → `RewardService.GiveReward`，XP/金币完全一致。
- **升级**：`AddXP` 把 XP 累加后，循环 `while XP >= GetXPRequiredForLevel(Level)`：扣阈值、`Level += 1`、记一次升级；一次大额奖励可跨多级。**溢出 XP 结转**（保留余数）。
- **技能点**：每升一级 `SkillPoints += 1`（本阶段只累计、不可消费、无技能树 UI、无效果）。
- **服务端权威**：所有 XP/等级/技能点变更只在服务端发生；客户端仅收 `PlayerDataRemote "Update"` 公开数据展示。
- **重开兼容**：按 R 的 `WaveService.ResetSession` 只重置波次/基地/塔/敌人，**完全不触碰** `PlayerDataService`，故 `Level/XP/SkillPoints/Coins/Pets` 不受重开影响。

## 4. XP Curve（公式）

集中式 helper（`PlayerDataService.GetXPRequiredForLevel`）：
```
xpRequired(level) = floor(100 * level ^ 2)
```
（`XP_CURVE_BASE = 100`，`XP_CURVE_EXPONENT = 2`。`XP` 表示当前等级内进度 `0 ~ xpRequired(Level)-1`。）

| 升级 | 所需 XP |
|-----:|--------:|
| L1 → L2  | 100 |
| L2 → L3  | 400 |
| L3 → L4  | 900 |
| L4 → L5  | 1,600 |
| L5 → L6  | 2,500 |
| L10 → L11 | 10,000 |
| L20 → L21 | 40,000 |
| L50 → L51 | 250,000 |

平方曲线 → 等级越高单级所需 XP 显著增多（后期大幅变慢），为未来大型/深度技能树节流点数产出；早期等级仍可较快达到。

## 5. Enemy XP Values（敌人 XP）

| 敌人 | 基础金币 | 基础 XP | 实际 XP（× rewardMult） |
|------|---------:|--------:|------------------------|
| `LagBlob`（普通） | 15 | **20** | 20（普通波 rewardMult = 1） |
| `BossLagBlob`（Boss） | 18 | **30** | Tier1 ~180 / Tier2 ~210 / Tier3 ~240（× `5 + tier`） |

- XP 复用 Phase 14 的 **同一 `rewardMult`**（普通怪 = 1；Boss = `5 + tier`），与金币缩放一致。
- Boss XP 显著高于普通怪，但 Tier 1 约 180（在平方曲线下 ≈ 早期约 1 级），里程碑感强而不至于早期暴涨。

## 6. Data Migration（v2 → v3）

- `DATASTORE_NAME = "PlayerData_v1"`（**不变**）；`CURRENT_DATA_VERSION = 2 → 3`。
- 迁移即 `reconcile`：以全新默认数据为底，逐字段合并存档：
  - **保留**：`Coins`、`Level`、`XP`、`Inventory.Pets`、`EquippedPets`、`CompletedTasks`、`Settings`、`Task`。
  - **新增**：`SkillPoints` —— 存档缺失则取默认 `0`；存在则规范化为非负整数。
- 不丢弃任何现有数据（不 wipe）。加载失败的会话仍按既有策略标记"不可保存"，避免覆盖云端好数据。

## 7. RewardService / Public Data

- `GiveReward` 结果新增（旧字段不变，向后兼容）：`skillPoints`、`skillPointsAdded`、`leveledUp`。
- `GetPublicData` 新增 `SkillPoints`，并将 `XpForNextLevel` 由常量改为 `GetXPRequiredForLevel(Level)`（随等级变化）。

## 8. UI / Feedback（最小改动）

- **MainUI**（小幅、非重设计）：新增一行 `Skill Points` 状态显示；`XP` 行沿用既有 `XP / XpForNextLevel`（阈值现随等级变化）；
  奖励反馈在升级时追加 `Level Up! +N Skill Point(s)`。
- **服务端日志**（QA 可见）：`[Reward] <player> 击杀 <enemy>：+C Coins，+X XP（当前 XP / Level / SP）`；升级时 `[Progression] <player> 升级！现 Level N，+K 技能点（共 S）`。

## 9. Edge Cases（边界）

- **负/非法 XP**：`AddXP` 把 `amount` 规范为非负整数（≤0 → 0），不会倒扣等级。
- **多级跳变**：循环每轮用**当前**等级阈值，逐级递增；大额奖励正确跨多级且每级各 +1 技能点。
- **溢出结转**：扣阈值后余数保留在 `XP`，下次继续累加。
- **迁移幂等**：已是 v3 的存档再次 reconcile 不变（字段已存在即原样保留）。
- **逃逸**：Boss/普通逃逸都不进入击杀路径 → 无 XP/金币。

## 10. Dependencies（依赖）

`PlayerDataService`（XP 曲线/升级/技能点/迁移/公开数据）、`RewardService`（汇总结果）、
`EnemyConfig`（`xpReward`）、`EnemyService`（解析+按 rewardMult 缩放 `xpReward`）、
`ServerInit.onEnemyKilled`（接线 + 日志）、`MainUI`（小幅显示）。`CombatService`/`TowerService` 不变（仍走同一 `onEnemyKilled`）。

## 11. Tuning Knobs（可调参数）

- `PlayerDataService`：`XP_CURVE_BASE`、`XP_CURVE_EXPONENT`。
- `EnemyConfig`：`LagBlob.xpReward`、`BossLagBlob.xpReward`（× Phase 14 Boss `rewardMult`）。

## 12. Acceptance Criteria（验收）

1. v2 存档安全迁移到 v3，金币/宠物/装备等全部保留；新字段 `SkillPoints` 默认 0。
2. 新玩家 `Level 1 / XP 0 / SkillPoints 0`。
3. 杀普通 `LagBlob` 得金币 + 小额 XP；杀 `BossLagBlob` 得更高金币 + 更高 XP。
4. 逃逸（含 Boss）不发金币、不发 XP。
5. XP 到阈值升级；溢出结转；一次大额奖励可多级；每级 +1 技能点。
6. 按 R 重开不重置 `Level/XP/SkillPoints/Coins/Pets`。
7. 宠物击杀与塔击杀都正确发 XP；同一敌人不重复发奖。
8. 既有波次/Boss/塔/宠物/重开均正常。

## 13. 安全与边界

- **不改**受保护文件：DummyTargetService / GameEventService / TaskService / TaskConfig.lua。
- **不新增 remote**（复用 `PlayerDataRemote "Update"` 与 `TaskRemote "Reward"`）。
- **不改** `DATASTORE_NAME`（仍 `PlayerData_v1`）；`CURRENT_DATA_VERSION` 2 → 3（本阶段要求的 schema 升级）。
- **不持久化**波次/会话进度；不实现技能树 UI / 技能效果 / 宠物技能（Phase 15 范围之外）。
