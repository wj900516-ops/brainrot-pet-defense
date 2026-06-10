# MVP Core Loop — 实现说明

> Phase 1 的唯一目标：跑通最小可玩核心循环。
> 不含：货币化 / 宠物 / 背包扩展 / 战斗 / 地图逻辑。

## 核心循环

```
玩家加入 → 初始化数据 → 分配起始任务 → 触发一次行动
        → 完成任务 → 发放金币 + 经验 → UI 刷新 → 任务重置/重复
```

**触发"一次行动"的来源：**
- **真实行动（Phase 2/3）**：在世界中击败训练假人（Training Dummy）。详见 [`Phase2-DummyTarget.md`](Phase2-DummyTarget.md)、[`Phase3-TaskConfig.md`](Phase3-TaskConfig.md)。
- **起始宠物（Phase 5）**：宠物在主人靠近假人时自动攻击，复用同一击败链路。详见 [`Phase5-StarterPet.md`](Phase5-StarterPet.md)。
- **调试按钮**：MainUI 的 `Do Action (Debug)` 按钮，受 `DEBUG_DO_ACTION` 开关控制，默认隐藏，仅供测试。

**当前进度流（Phase 3）**：
```
GameEventService.EnemyDefeated:Fire(player, enemyId)
  → ServerInit 监听 → TaskService.HandleEnemyDefeated(player, enemyId)   -- type/target 匹配
      → 返回结果对象 { progressed, completed, task, reward, reason }
  → ServerInit.pushProgressResult(player, result)                        -- 按结果推送 Task/Data/Reward
```
调试按钮路径相同，只是改用 `TaskService.AddProgress(player, 1)`（不做匹配），且默认禁用。

## 模块与职责（分层，无循环依赖）

| 层 | 文件 | 职责 | 依赖 |
|----|------|------|------|
| 数据 | `ServerScriptService/Services/PlayerDataService.lua`（Phase 4/6/15） | 玩家数据 + DataStore 持久化；Phase 15：渐进 XP 曲线 `GetXPRequiredForLevel`、升级 +1 技能点、`SkillPoints` 字段、v2→v3 迁移 | 无 |
| 奖励 | `ServerScriptService/Services/RewardService.lua`（Phase 15） | 发金币/经验，返回结构化结果（含 `skillPoints`/`skillPointsAdded`/`leveledUp`） | PlayerDataService |
| 任务 | `ServerScriptService/Services/TaskService.lua` | 分配/跟踪/结算任务 | RewardService, PlayerDataService |
| 网络 | `ReplicatedStorage/Remotes/Net.lua` | 按需创建/获取 RemoteEvent | 无 |
| 宠物 | `ServerScriptService/Services/PetService.lua` | 起始宠物生成/跟随/攻击；只读 `GetActivePet` | PlayerDataService, PetConfig, DummyTargetService |
| 敌人 | `ServerScriptService/Services/EnemyService.lua`（Phase 8/10/14） | 敌人生成/航点移动/受伤/死亡/逃逸；`ClearAll`/`GetBasePosition`；Phase 14：`SpawnEnemy(id, {hpMult,speedMult,rewardMult,isBoss})` 难度倍率 + 配置驱动 Boss 体型/颜色 | EnemyConfig |
| 波次/会话 | `ServerScriptService/Services/WaveService.lua`（Phase 8/9/13/14） | 波次进程 + 基地血量 + 失败条件 + 基地状态板 + 失败后重开（ResetSession）；Phase 14：分梯队难度 + 每 5 波 Boss（`buildWavePlan`/`getWaveTier`/`isBossWave`） | EnemyService |
| 战斗 | `ServerScriptService/Services/CombatService.lua`（Phase 8） | 宠物→敌人伤害判定；击杀回调 | PetService, EnemyService |
| 塔 | `ServerScriptService/Services/TowerService.lua`（Phase 11/12） | 服务端校验+放置占位塔；Phase 12 自动攻击范围内最近敌人 | PlayerDataService, EnemyService, TowerConfig |
| 编排 | `ServerScriptService/ServerInit.server.lua` | 连接 PlayerAdded、接线 Remote、击杀→奖励 | 全部 |
| 界面 | `StarterGui/MainUI/MainUI.client.lua` | 代码构建 UI、收发 Remote | Net |

**关键原则**：Service 层不感知 Remote。所有客户端通信集中在 `ServerInit`（服务端）与 `MainUI`（客户端）两个编排层，便于测试与替换。

## 战斗循环（Phase 8）

```
WaveService（周期）→ EnemyService.SpawnEnemy → 敌人朝基地移动
CombatService（每帧）→ 已装备宠物攻击范围内最近敌人 → EnemyService.DamageEnemy
  → 致命一击 → ServerInit.onEnemyKilled → RewardService.GiveReward({rewardCoins, rewardXP}) → pushData
```
Phase 15：击杀同时发放 XP（`enemy.xpReward`，普通怪小额、Boss 更高且随梯队 rewardMult 放大）；XP 升级、每级 +1 技能点（见上方数据结构说明）。逃逸不发 XP/金币。
敌人/宠物为服务端 Anchored Part，自动复制，**无新增 remote**；战斗 server-authoritative。详见 [`Phase8-CombatLoop.md`](Phase8-CombatLoop.md)。

## 防御会话（Phase 9）

```
WaveService：第 N 波生成固定数量 LagBlob → 全部解决（击杀/逃逸）→ 延迟 → 下一波
击杀 → 奖励（Phase 8/8.5）；逃逸到达基地 → Base HP -1（不奖励）；Base HP=0 → 会话失败、停止刷怪
基地状态板（世界 Billboard）显示 Wave / Base HP / 失败，**不改 MainUI**、无持久化。详见 [`Phase9-WaveBaseHP.md`](Phase9-WaveBaseHP.md)。

Phase 10：敌人沿 `Workspace.EnemyPath` 航点（缺失则兜底直线）从路径起点走向终点（基地）；到达终点 = 逃逸扣血。详见 [`Phase10-RoutePathing.md`](Phase10-RoutePathing.md)。

Phase 12：已放置的塔自动攻击范围内最近敌人，击杀复用宠物的 `onEnemyKilled` 奖励通道；`DamageEnemy` 的一次性守卫保证不重复发奖。详见 [`Phase12-TowerAttack.md`](Phase12-TowerAttack.md)。

Phase 14：波次难度分梯队（每 5 波一梯队），每第 5 波（5/10/15…）为 Boss 波。难度全部由 `buildWavePlan(waveNumber)`
（纯函数，确定性，派生自 waveNumber）给出敌人数量与 hp/speed/reward 倍率，再传给 `EnemyService.SpawnEnemy`。
Boss 为 `BossLagBlob` 配置项（更大体型/紫色/更高基础奖励）× Boss 倍率：更肉、更慢、奖励更高，仍走同一击杀/逃逸结算（一次性发奖、逃逸不发奖）。
状态板加显 `Tier` 与 `BOSS`。重开把 waveNumber 归 0 即清空所有梯队/Boss 状态。详见 [`Phase14-WaveDifficulty.md`](Phase14-WaveDifficulty.md)。
```

## Remote 协议（action 字符串 + 负载）

`PlayerDataRemote`
- C→S `"Request"` → 服务端回推一次公开数据
- S→C `"Update", publicData` → `{ Coins, Level, XP, XpForNextLevel, SkillPoints }`（Phase 15：`XpForNextLevel` 随等级变化、新增 `SkillPoints`）

`TaskRemote`
- C→S `"Request"` → 回推当前任务
- C→S `"DoAction"` → **默认禁用的调试通道**。自 Phase 2 起，真实进度来自训练假人循环；
  服务端的 `ENABLE_DEBUG_DO_ACTION` 默认为 `false`，此请求会被**安全忽略**（不加进度、不结算、不发奖励）。
  仅当显式开启该开关（且客户端 `DEBUG_DO_ACTION=true` 才会显示按钮）时，才会走 `TaskService.AddProgress` → `ServerInit.pushProgressResult`。
- S→C `"Update", task` → 公开任务数据 `{ title, progress, goal, rewardCoins, rewardXP }`（Phase 3：配置驱动，详见 `Phase3-TaskConfig.md`）
- S→C `"Reward", rewardResult` → `{ coinsAdded, xpAdded, newCoins, newXP, level }`

`PetRemote`（Phase 7）
- C→S `"RequestPets"` → 回推宠物列表
- C→S `"EquipPet", uid` / `"UnequipPet", uid` → 服务端校验后改装备 + 刷新宠物 + 回推
- S→C `"Pets", publicPets` → `{ { uid, petId, displayName, equipped } }`（加入时也推一次）。详见 [`Phase7-PetUI.md`](Phase7-PetUI.md)

`TowerRemote`（Phase 11 / 11.5）
- C→S `"PlaceTower", groundPoint?` → 服务端完整校验（金币/距路径/距塔/距玩家/竖直）后扣币放置
  （Phase 11.5：客户端鬼影预览发送鼠标地面落点；为空则回退玩家脚下）
- S→C `"Result", { success, reason, cost? }` → 客户端放置反馈。详见 [`Phase11-TowerPlacement.md`](Phase11-TowerPlacement.md) / [`Phase11_5-TowerPlacementUX.md`](Phase11_5-TowerPlacementUX.md)

`RestartRemote`（Phase 13）
- C→S `"Restart"`（仅意图）→ 仅失败后允许：清敌人/塔 + 重置基地/波次 + 重启刷怪
- S→C `"Result", { success, reason }`；`"SessionState", { failed }`（失败/重开广播、加入单发）。详见 [`Phase13-RunRestart.md`](Phase13-RunRestart.md)

RemoteEvent 实例由服务端在运行时创建于 `ReplicatedStorage/Remotes/` 文件夹下，**无需在 Studio 手动创建**。

## 数据结构（PlayerDataService）

```lua
{
  DataVersion = 3,                 -- Phase 15：新增 SkillPoints（Phase 6 起含宠物库存/装备）
  ProgressionVersion = 1,          -- Phase 15：技能点经济版本标记（独立于 DataVersion，控制进度迁移）
  Coins = 0, Level = 1, XP = 0,
  SkillPoints = 0,                 -- Phase 15：升级累计的技能点（暂不可消费）
  CompletedTasks = {},             -- [taskId] = 完成次数
  Inventory = { Pets = { { uid, petId, acquiredAt } } },  -- Phase 6
  EquippedPets = { "starter_toast_1" },                    -- Phase 6（数组，单槽）
  Settings = {},
  Task = { currentTaskId, currentTaskProgress, taskChainIndex },  -- Phase 3，持久化于 Phase 4
}
```
经验规则（Phase 15）：升到下一级所需 XP = `floor(100 * Level^2)`（集中于 `PlayerDataService.GetXPRequiredForLevel`；L1→2=100、L5→6=2,500、L10→11=10,000、L50→51=250,000）。
XP 满阈值即升级、扣阈值、`SkillPoints += 1`、溢出结转；一次大额奖励可跨多级。重开（R）不重置玩家进度（Level/XP/SkillPoints/Coins/Pets）。
持久化与迁移见 [`Phase4-Persistence.md`](Phase4-Persistence.md)；宠物拥有/装备见 [`Phase6-PetInventory.md`](Phase6-PetInventory.md)；玩家进度见 [`Phase15-PlayerProgression.md`](Phase15-PlayerProgression.md)。
进度迁移（Phase 15）：技能点经济为全新系统，用**独立标记** `ProgressionVersion`（当前 `1`）判断是否已初始化（不看 `DataVersion`，因早期 Play Solo 曾把旧进度写成 `DataVersion=3`）。无 `ProgressionVersion` 或 `<1` 的存档把 `Level/XP/SkillPoints` **重置**为 `1/0/0` 并标记 `ProgressionVersion=1`，金币/宠物/装备/任务等保留；`ProgressionVersion>=1` 的存档正常保留进度（不重复重置）。

## 下一步的扩展点（给后续 CCGS / Cursor）

1. ~~**持久化**：在 `PlayerDataService` 内接入 DataStore~~ —— **✅ 已在 Phase 4 完成**：
   `PlayerDataService` 通过原生 `DataStoreService`（安全封装：pcall + 有限重试 + 失败回退 + BindToClose）
   持久化 Coins/Level/XP/任务状态等；`TaskService.RestoreOrAssign` 负责重进后恢复任务。详见 [`Phase4-Persistence.md`](Phase4-Persistence.md)。
2. ~~**更多任务**：把 `TaskService` 内的 `STARTER_TASK` 提取为 `ReplicatedStorage/Config/TaskConfig`~~ —— **✅ 已在 Phase 3 完成**：
   任务现由 [`ReplicatedStorage/Config/TaskConfig.lua`](../src/ReplicatedStorage/Config/TaskConfig.lua) 数据驱动，
   支持起始任务链与可重复 fallback。详见 [`Phase3-TaskConfig.md`](Phase3-TaskConfig.md)。
3. ~~**真实行动**：把 `"DoAction"` 测试按钮替换为真实游戏事件~~ —— **✅ 已在 Phase 2 完成**：
   真实进度现由训练假人循环（`DummyTargetService` → `GameEventService.EnemyDefeated` → `TaskService.AddProgress`）驱动；
   `"DoAction"` 已降级为默认禁用的调试通道。详见 [`Phase2-DummyTarget.md`](Phase2-DummyTarget.md)。
4. **防作弊（进行中）**：训练假人路径已具备服务端校验 —— 每玩家命中冷却、单次击败 one-shot 守卫、
   以及服务端到角色 `HumanoidRootPart` 的距离校验（`MAX_VALID_HIT_DISTANCE`）。后续真实战斗系统应沿用同样的服务端权威校验。
5. **玩家技能树（设计中，Phase 16A）**：用 Phase 15 的 `SkillPoints` 投资 4 大分支（Economy/Tower/Pet/Defense）的永久强化。
   当前仅有**纯数据脚手架** [`SkillTreeConfig.lua`](../src/ReplicatedStorage/Config/SkillTreeConfig.lua)（**无人 require，不影响玩法**）
   与设计规格 [`Phase16A-SkillTreeDesign.md`](Phase16A-SkillTreeDesign.md)。Phase 16B 才接入：持久化 `SkillTree = { Version = 1, Unlocked = {...} }`（拟 `CURRENT_DATA_VERSION` 3→4，版本标记内嵌 `SkillTree.Version`；只存 `[skillId]=rank`，派生量动态计算）、
   服务端消费端点、集中式 `SkillEffectResolver` 与各系统 hook（先上 3 个技能）。**本阶段不改 PlayerDataService、不 bump DataVersion、不改 MainUI、不碰受保护文件。**
