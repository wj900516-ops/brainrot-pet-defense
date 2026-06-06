# Phase 2 — Training Dummy Loop（首个真实游戏行动）

> 目标：用最小的"真实交互"替换 Phase 1 的纯调试按钮，把游戏内动作接到任务进度上。
> 不含：完整战斗 / 敌人 AI / 波次 / 商业化 / 背包 / DataStore。

## 做了什么

在世界中用代码生成一个**训练假人（Training Dummy）**。玩家点击攻击它，
服务端处理命中与血量，击败时通过**服务端事件总线**广播，由编排层接到既有的奖励流程。

## 事件流（精确）

```
玩家点击假人 (ClickDetector.MouseClick，服务端事件)
  → DummyTargetService.HandleHit(player)        -- 冷却校验 + 扣血 + 命中反馈
      → GameEventService.TargetInteracted:Fire(player, "TrainingDummy")   -- 每次有效命中（可选，不发奖励）
  → HP 归零 → alive=false（保证只触发一次）
      → GameEventService.EnemyDefeated:Fire(player, "TrainingDummy")
          → ServerInit 监听 EnemyDefeated.Event
              → grantActionProgress(player)
                  → TaskService.AddProgress(player, 1)   ← 复用 Phase 1 既有通道（未改动）
                      → CompleteTask → RewardService → PlayerDataService
                  → 推送 Task / Data / Reward 到 MainUI
  → RESPAWN_DELAY 后假人重生
```

## 分层与边界

| 模块 | 角色 | 是否发奖励 |
|------|------|-----------|
| `DummyTargetService` | 纯机制：生成/命中/血量/重生，击败时广播事件 | **否** |
| `GameEventService` | 极简服务端事件总线（BindableEvent），解耦生产者与消费者 | **否** |
| `ServerInit` | 编排层：监听 `EnemyDefeated` → 调用统一进度入口 | 决策点 |
| `TaskService` / `RewardService` / `PlayerDataService` | Phase 1 既有逻辑，未改动 | 是（既有） |

**服务端权威**：伤害、血量、击败、进度、奖励全部在服务端。
**客户端零信任**：客户端不发送原始进度；`ClickDetector.MouseClick` 本身就是服务端事件，
因此本阶段**未新增任何客户端 RemoteEvent**。调试按钮的 `"DoAction"` 也只是"请求"，进度仍由服务端决定。

## 防刷 / 冷却

- **服务端距离校验** `MAX_VALID_HIT_DISTANCE = 40`：每次命中都在服务端计算玩家角色
  `HumanoidRootPart` 到假人的实际距离，超出则判定无效。**不依赖** `ClickDetector.MaxActivationDistance`
  （客户端可被篡改）。距离校验不通过 → 不扣血、不加进度。
- **每玩家命中冷却** `HIT_COOLDOWN = 0.2s`：同一玩家两次有效命中需间隔 ≥0.2s，防连点刷。
- **单次击败保证**：扣血归零时立即 `alive=false`，收尾阶段的多余点击不会重复触发 `EnemyDefeated`。
- **重生延迟** `RESPAWN_DELAY = 1.5s`：击败后假人进入不可命中状态直到重生。
- **离开清理**：`Players.PlayerRemoving` 时清除该玩家的命中冷却记录。

## 可调参数（DummyTargetService 顶部）

| 参数 | 默认 | 含义 |
|------|------|------|
| `MAX_HP` | 3 | 几次点击击败 |
| `HIT_COOLDOWN` | 0.2 | 每玩家命中冷却（秒） |
| `RESPAWN_DELAY` | 1.5 | 击败后重生延迟（秒） |
| `SPAWN_POSITION` | (0, 5, -12) | 假人世界坐标（按地图微调） |
| `CLICK_DISTANCE` | 32 | ClickDetector 最大激活距离（仅客户端便利） |
| `MAX_VALID_HIT_DISTANCE` | 40 | **服务端**距离校验上限（HRP→假人） |

## 给后续 CCGS / Codex 的扩展点

1. 多个假人 / 每玩家独立假人：`DummyTargetService` 已与进度解耦，扩展不影响奖励逻辑。
2. 更多敌人类型：复用 `GameEventService.EnemyDefeated:Fire(player, enemyId)`，`ServerInit` 可按 `enemyId` 分流。
3. 真实战斗：把 ClickDetector 换成攻击判定即可，事件契约不变。
4. 任务多样化：把 `TaskService` 的 `STARTER_TASK` 提取为 `TaskConfig`（Phase 1 已记录）。
