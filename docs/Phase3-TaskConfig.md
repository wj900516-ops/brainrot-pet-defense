# Phase 3 — Config-Driven Task Chain（配置驱动的任务链）

> 目标：把硬编码的起始任务改为配置驱动，并支持一条短的多任务起始链。
> 不含：DataStore / 宠物 / 商业化 / 复杂战斗。

## 概览

Phase 2 只有一个会重复的任务。Phase 3 引入 **TaskConfig**：任务以数据形式定义，
`TaskService` 据此为玩家分配并**按链推进**，链结束后**循环可重复 fallback** 任务。

## TaskConfig

位置：`ReplicatedStorage/Config/TaskConfig.lua`（沿用项目既有的 `Config/` 约定）。

```lua
TaskConfig.StarterChain = {
  { id = "defeat_training_dummy_1", type = "DefeatEnemy", target = "TrainingDummy",
    title = "Defeat 1 Training Dummy",   goal = 1, rewardCoins = 50,  rewardXP = 25 },
  { id = "defeat_training_dummy_3", type = "DefeatEnemy", target = "TrainingDummy",
    title = "Defeat 3 Training Dummies", goal = 3, rewardCoins = 150, rewardXP = 75 },
}
TaskConfig.RepeatableFallbackId = "defeat_training_dummy_3"
```

字段：`id` / `type` / `target` / `title` / `goal` / `rewardCoins` / `rewardXP`。

## 起始任务链 & 可重复 fallback

```
加入 → 任务1 "Defeat 1 Training Dummy" (goal 1)
  击败假人 ×1 → 奖励 50/25 → 推进 → 任务2 "Defeat 3 Training Dummies" (goal 3)
  击败假人 ×3 → 奖励 150/75 → 链结束 → 循环 fallback(=任务2) → 之后持续可重复
```

- 完成任务后 `TaskService` 自动推进到链中的下一个任务。
- 链结束后循环 `RepeatableFallbackId` 指向的任务；若该 id 缺失/不在链中，则默认循环链中最后一个。

## 事件如何映射到任务进度（Event Matching）

```
DummyTargetService（假人被击败）
  → GameEventService.EnemyDefeated:Fire(player, "TrainingDummy")
      → ServerInit 监听 EnemyDefeated.Event
          → TaskService.HandleEnemyDefeated(player, "TrainingDummy")
              ├─ 当前任务 type == "DefeatEnemy" 且 target == "TrainingDummy"?
              │     是 → AddProgress(+1)（达标则结算+推进+发奖励）
              │     否 → 返回非进度结果（reason = type_mismatch / target_mismatch），不发奖励
          → ServerInit.pushProgressResult 按结果推送 Task / Data / Reward
```

**只在匹配时才加进度/发奖励。** 不匹配的事件被安全忽略。

## 结果对象（TaskService → ServerInit）

`AddProgress` 与 `HandleEnemyDefeated` 返回一致结构：

```lua
{
  progressed = boolean,        -- 是否实际加了进度
  completed  = boolean,        -- 本次是否完成了一个任务
  task       = publicTaskData, -- 操作后的"当前任务"公开数据（完成后即为下一个任务）
  reward     = rewardResult?,  -- 完成时的奖励结果，否则 nil
  reason     = string?,        -- "progressed" / "completed" / "no_task" / "type_mismatch" / "target_mismatch"
  -- completedTaskId : string? -- 完成时附带
}
```

`publicTaskData` 与 MainUI 兼容：`{ title, progress, goal, rewardCoins, rewardXP }`。
完成后 `ServerInit` 立即推送下一个任务 → UI 自动切换，无需重启或额外操作。

## 服务边界（未变）

- `DummyTargetService` **不** require/调用 `TaskService` / `RewardService` / `PlayerDataService`。
- 匹配 + 进度 + 推进在 `TaskService`；推送在 `ServerInit`；奖励在 `RewardService`；状态在 `PlayerDataService`。
- `MainUI` / `Net.lua` / `GameEventService` 未改动。调试 `DoAction` 仍默认禁用（`DEBUG_DO_ACTION` / `ENABLE_DEBUG_DO_ACTION` 均为 false）。

## 防御式配置处理

`TaskService` 在加载时对配置做校验，坏配置不会崩服：
- TaskConfig 无法加载 / 非表 → 使用内置兜底任务（pcall 保护 require）。
- 任务缺少合法 `id` → 跳过该任务并告警。
- `goal` 缺失/非法 → 回退为 `1`。
- `rewardCoins` / `rewardXP` 缺失/非法 → 缺省为 `0`。
- `type` 缺失 → 回退为 `"DefeatEnemy"`。
- 起始链为空 → 使用内置兜底任务。

## 如何新增任务类型（未来）

1. 在 `TaskConfig` 增加任务定义，使用新的 `type`（如 `"InteractTarget"` / `"EarnCoins"`）。
2. 在产生该事件的系统中通过 `GameEventService` 广播对应事件（如 `TargetInteracted`）。
3. 在 `TaskService` 增加一个匹配入口（仿照 `HandleEnemyDefeated`），按 `type`/`target` 匹配后调用 `AddProgress`。
4. 在 `ServerInit` 把该事件路由到新的匹配入口并 `pushProgressResult`。

> 核心循环与分层总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)；假人机制见 [`Phase2-DummyTarget.md`](Phase2-DummyTarget.md)。
