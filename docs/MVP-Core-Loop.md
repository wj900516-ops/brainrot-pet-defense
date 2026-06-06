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
| 数据 | `ServerScriptService/Services/PlayerDataService.lua` | 内存玩家数据；预留 DataStore 接口 | 无 |
| 奖励 | `ServerScriptService/Services/RewardService.lua` | 发金币/经验，返回结构化结果 | PlayerDataService |
| 任务 | `ServerScriptService/Services/TaskService.lua` | 分配/跟踪/结算任务 | RewardService, PlayerDataService |
| 网络 | `ReplicatedStorage/Remotes/Net.lua` | 按需创建/获取 RemoteEvent | 无 |
| 编排 | `ServerScriptService/ServerInit.server.lua` | 连接 PlayerAdded、接线 Remote | 全部 |
| 界面 | `StarterGui/MainUI/MainUI.client.lua` | 代码构建 UI、收发 Remote | Net |

**关键原则**：Service 层不感知 Remote。所有客户端通信集中在 `ServerInit`（服务端）与 `MainUI`（客户端）两个编排层，便于测试与替换。

## Remote 协议（action 字符串 + 负载）

`PlayerDataRemote`
- C→S `"Request"` → 服务端回推一次公开数据
- S→C `"Update", publicData` → `{ Coins, Level, XP, XpForNextLevel }`

`TaskRemote`
- C→S `"Request"` → 回推当前任务
- C→S `"DoAction"` → **默认禁用的调试通道**。自 Phase 2 起，真实进度来自训练假人循环；
  服务端的 `ENABLE_DEBUG_DO_ACTION` 默认为 `false`，此请求会被**安全忽略**（不加进度、不结算、不发奖励）。
  仅当显式开启该开关（且客户端 `DEBUG_DO_ACTION=true` 才会显示按钮）时，才会走 `TaskService.AddProgress` → `ServerInit.pushProgressResult`。
- S→C `"Update", task` → 公开任务数据 `{ title, progress, goal, rewardCoins, rewardXP }`（Phase 3：配置驱动，详见 `Phase3-TaskConfig.md`）
- S→C `"Reward", rewardResult` → `{ coinsAdded, xpAdded, newCoins, newXP, level }`

RemoteEvent 实例由服务端在运行时创建于 `ReplicatedStorage/Remotes/` 文件夹下，**无需在 Studio 手动创建**。

## 数据结构（PlayerDataService）

```lua
{
  Coins = 0, Level = 1, XP = 0,
  CompletedTasks = {},  -- [taskId] = 完成次数
  Inventory = {}, Settings = {},
}
```
经验规则：`XP_PER_LEVEL = 100`，XP 满 100 自动升级并归零进入下一级。

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
