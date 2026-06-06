# MVP Core Loop — 实现说明

> Phase 1 的唯一目标：跑通最小可玩核心循环。
> 不含：货币化 / 宠物 / 背包扩展 / 战斗 / 地图逻辑。

## 核心循环

```
玩家加入 → 初始化数据 → 分配起始任务 → 点击 "Do Action"
        → 完成任务 → 发放金币 + 经验 → UI 刷新 → 任务重置/重复
```

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
- C→S `"DoAction"` → 进度 +1，完成则结算
- S→C `"Update", task` → `{ id, title, goal, progress, rewardCoins, rewardXP }`
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

1. **持久化**：在 `PlayerDataService.InitData`（读档）与 `ClearData`（存档）内接入 DataStore，其余代码无需改动。
2. **更多任务**：把 `TaskService` 内的 `STARTER_TASK` 提取为 `ReplicatedStorage/Config/TaskConfig`，并支持任务队列/链。
3. **真实行动**：把 `"DoAction"` 测试按钮替换为真实游戏事件（如击杀敌人）调用 `TaskService.AddProgress`。
4. **防作弊**：`DoAction` 当前无频率限制，正式化时需在服务端校验。
