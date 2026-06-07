# Phase 8 — Enemy Wave / Combat Loop MVP（敌人波次与战斗循环）

> 目标：跑通首个可玩战斗循环 ——
> 玩家装备宠物 → 敌人生成 → 敌人朝基地移动 → 宠物自动攻击范围内最近敌人 → 敌人死亡 → 玩家获得奖励。
> server-first、最小可行、不过度设计。

## 核心战斗循环

```
WaveService（每 4s，受存活上限约束）
  → EnemyService.SpawnEnemy("LagBlob")          -- 在出生点生成占位敌人（Anchored Part，自动复制）
EnemyService Heartbeat
  → 敌人朝 BASE_POSITION 直线移动；到达基地 → 逃逸移除（本阶段无基地血量）
CombatService Heartbeat（每位玩家）
  → PetService.GetActivePet(player)             -- 未装备则 nil → 不攻击
  → 找到宠物范围内最近的存活敌人
  → 按宠物 attackInterval 调用 EnemyService.DamageEnemy(enemy, attackDamage)
      → enemy.hp <= 0 → alive=false（一次性）→ onEnemyKilled(ownerPlayer, enemy)
ServerInit.onEnemyKilled
  → RewardService.GiveReward(player, { rewardCoins = enemy.reward })   -- 复用既有契约（窄适配）
  → pushData(player)                            -- 刷新 MainUI 金币/等级/经验
```

## 敌人生命周期（EnemyService）

| 字段 | 含义 |
|------|------|
| `enemyId` | 类型标识（如 `LagBlob`，来自 `ReplicatedStorage/Config/EnemyConfig`） |
| `hp` / `maxHp` | 当前 / 最大血量 |
| `speed` | 移动速度（studs/秒） |
| `reward` | 击杀奖励（金币；来自 EnemyConfig.killReward） |
| `alive` | 存活/死亡状态 |

- **生成**：`SpawnEnemy(enemyId)` 在 `SPAWN_POSITION (0,3,-40)` 生成占位 Part（绿色方块 + 血量 Billboard）。
- **移动**：每帧朝 `BASE_POSITION (0,3,0)` 直线移动（无复杂寻路）。
- **受伤**：`DamageEnemy(enemy, amount)` 扣血并刷新血条；**返回 true 当且仅当这一击造成击杀**（`alive` 一次性置 false，保证只结算一次）。
- **死亡**：销毁模型并在清理过程移除记录。
- **逃逸**：到达基地（距离 ≤ 4）→ 直接移除（本阶段无基地血量，不扣血、不奖励）。

复用既有 `EnemyConfig`（`LagBlob`：health 24 / speed 4 / killReward 15；Phase 8 调平了 health/speed 以保证可击杀）。

## 战斗归属模型（CombatService）

- 战斗完全 **server-authoritative**：是否攻击、打谁、打多少，全部服务端决定，不信任客户端。
- 仅 **"拥有已装备宠物"** 的玩家参与战斗：`PetService.GetActivePet(player)` 在未装备/未生成时返回 `nil` → 不攻击（满足"卸下的宠物不攻击"）。
- 每位玩家的宠物攻击其 **范围内最近的存活敌人**，按宠物 `attackInterval` 冷却。
- **击杀归属**：造成"致命一击"的宠物，其 **主人** 获得该敌人奖励（`onEnemyKilled(ownerPlayer, enemy)`）。
- CombatService 自带每玩家战斗冷却表（`PlayerRemoving` 清理），**不污染 PetService 内部记录**，只读 `GetActivePet`。

宠物战斗属性来自 `PetConfig`（`starter_toast`：`attackRange = 28`、`attackDamage = 15`、`attackInterval = 1.5`；
Phase 8 调平：LagBlob 24 HP ÷ 15 ≈ 2 击、约 1.5s 内可击杀，敌人 speed 4 时有充足时间）。

## 奖励触发（reward trigger）

- 仅在 `DamageEnemy` 返回"致命一击"时触发一次 → `onEnemyKilled`。
- 奖励经 **既有 `RewardService.GiveReward(player, task)`** 发放：传入 `{ rewardCoins = enemy.reward, rewardXP = 0 }`
  这一"reward 形状的表"即**窄适配**，**不修改 RewardService 的公开契约**。
- 发奖励后 `pushData(player)` 刷新客户端金币/等级/经验（MainUI 既有 UI，无需改动）。
- **每个敌人只奖励一次**：`alive` 一次性置 false，死亡后不再可被伤害/结算。

### Phase 8.5：奖励反馈（reward feedback）

击杀后 `ServerInit` 复用**既有**奖励反馈通道把 `GiveReward` 的结果回推：
`taskRemote:FireClient(player, "Reward", reward)`。MainUI 早已监听该 `"Reward"` 事件并显示
`"+N Coins, +M XP!"`（如 `+15 Coins, +0 XP!`）。

- **未改动 MainUI**、**未新增 remote**：纯复用既有客户端反馈路径。
- 服务端仍是唯一真相：客户端只是显示，不参与奖励决策。
- 因战斗仅发金币（XP=0），反馈会显示 `+0 XP`（轻微外观项，见"已知限制"）。

## 网络

- 敌人/宠物均为服务端 **Anchored Part**，自动复制到客户端 —— **本阶段未新增任何 RemoteEvent/RemoteFunction**。
- 不存在让客户端伪造伤害/奖励的变更类远程：战斗与奖励决策全在服务端。

## 边界 / 保护文件

**未修改**任何受保护文件：
`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService`（仅调用）/ `TaskConfig.lua` / `MainUI.client.lua`。
`Net.lua` 未改动；`EnemyConfig` 复用未改动。
**未改动** DataStore 名称（`PlayerData_v1`）与 `CURRENT_DATA_VERSION`（`2`）—— 本阶段无持久化 schema 变化。

Phase 7 宠物 UI / 装备流程行为保持不变（仅新增只读 `PetService.GetActivePet` 与 `PetConfig` 战斗属性）。

## 明确的范围外（Out of Scope）

- 基地血量 / 玩家失败条件（敌人逃逸仅移除）。
- 复杂寻路 / 路径点（仅直线移动）。
- 多敌人类型曲线 / Boss / 难度递增（仅单一 `LagBlob`、固定间隔）。
- 投射物 / 视觉特效 / 伤害数字。
- 战斗经验（击杀仅发金币；XP 仍来自任务循环）。
- 商店 / 抽卡 / 高级 UI / 多宠物协同。

## 已知限制

- 宠物跟随玩家；若玩家远离基地路径，宠物可能够不到敌人 → 敌人逃逸。MVP 设计为"在基地附近防守"。
- 宠物同时仍会攻击训练假人（Phase 5/7）与敌人（Phase 8），二者独立冷却，互不影响。
- 刷怪为固定节奏，无难度曲线。
- 奖励反馈复用既有 `"+N Coins, +M XP!"` 文案；战斗仅发金币时会显示 `+0 XP`（为避免改 MainUI 而接受的轻微外观项）。
- Phase 8.5：`PetService` 的"无已装备宠物，跳过生成"日志默认静默（`DEBUG_LOG=false`），仅调试时打印；行为不变。

## 未来扩展点

- 基地血量 + 失败/胜利条件。
- 波次配置化（`WaveConfig`：每波数量/类型/间隔/Boss）。
- 多敌人类型与路径点寻路。
- 投射物与命中特效；伤害数字。
- 战斗也产出经验 / 掉落。

> 宠物攻击与装备见 [`Phase5-StarterPet.md`](Phase5-StarterPet.md) / [`Phase7-PetUI.md`](Phase7-PetUI.md)；核心循环总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
