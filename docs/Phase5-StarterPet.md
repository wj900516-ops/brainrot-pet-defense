# Phase 5 — Starter Pet + Simple Attack Loop（起始宠物与简单攻击循环）

> 目标：给每位玩家一只起始宠物，宠物自动攻击训练假人，复用既有的击败/任务/奖励链路。
> 范围（Option A）：复用 `DummyTargetService.HandleHit(owner)`，**不修改** DummyTargetService。
> 不含：多宠物 / 宠物背包 UI / 抽卡 / 商店 / 商业化 / 波次 / 复杂战斗 / 宠物升级 / 客户端 remote。

## 做了什么

- 每位玩家在数据/任务恢复后获得一只**占位起始宠物**（代码构建，无需美术）。
- 宠物在主人附近跟随。
- 服务端按攻击间隔调用既有的 `DummyTargetService.HandleHit(owner)`。
- 假人被击败时，仍由**既有链路**结算进度与奖励 —— 宠物本身不发放任何奖励。

## 攻击循环（事件流）

```text
PetService 心跳循环（每位主人，按 attackInterval）
  → DummyTargetService.HandleHit(owner)            ← 既有方法，未改动
      → 自带校验：假人存活? 主人在有效距离? 每玩家冷却?
          → 满足 → 扣血；HP 归零 → GameEventService.EnemyDefeated(owner, "TrainingDummy")
              → ServerInit 监听 → TaskService.HandleEnemyDefeated → RewardService → PlayerDataService
              → 推送 Task/Data/Reward 给 MainUI
          → 不满足 → 静默 no-op（不扣血、不进度）
```

## Option A 距离模型（本阶段的关键决策）

`HandleHit(owner)` 的距离校验基于**主人**角色的 `HumanoidRootPart` 到假人的距离
（`MAX_VALID_HIT_DISTANCE`）。因此：

- 宠物只有在**主人位于假人有效范围内**时才能真正命中（"把宠物带到假人旁边"）。
- 这让我们可以**原样复用** `DummyTargetService`，零改动，最小风险。

### 为什么复用 DummyTargetService 不改动

- 假人的存活/血量/击败/重生/`EnemyDefeated` 广播全部已在 `HandleHit` 内闭环且 server-authoritative。
- `HandleHit` 在条件不满足时**静默 no-op**，所以宠物只需"按间隔尝试命中"，无需查询假人状态，
  也无需把伤害逻辑复制到 PetService —— 既保持单一数据源（假人血量），又不破坏既有边界。

## 配置（PetConfig）

位置：`ReplicatedStorage/Config/PetConfig.lua`（沿用 `Config/` 约定）。

| 字段 | 起始宠物值 | 含义 |
|------|-----------|------|
| `id` | `starter_toast` | 唯一标识 |
| `displayName` | `Toasty` | 头顶名 |
| `attackInterval` | `2.25` | 攻击间隔（秒），保守取值，避免过快完成任务 |
| `followOffset` | `(3, 2, 3)` | 相对主人 HRP 的跟随偏移 |
| `followStiffness` | `0.15` | 每帧跟随插值系数 |
| `visual.size/color/material` | 球体/暖黄/SmoothPlastic | 占位视觉 |

> 假人 3 HP × 2.25s ≈ 约 6.75s 自动击败一次（任务 1 完成；任务 2 需 3 次）。

## 生命周期 / 清理

- **生成**：`PlayerAdded` → 加载数据 → 恢复任务 → 推送 UI → `PetService.SpawnPet(player)`。
- **跟随 + 攻击**：单个 `RunService.Heartbeat` 循环驱动所有宠物（跟随插值 + 按间隔 `HandleHit`）。
- **清理**：`PetService` 在 `Players.PlayerRemoving` 销毁宠物模型并清除 `petsByPlayer[player]`；
  `ServerInit.onPlayerRemoving` 也会调用 `DespawnPet`（幂等，双保险）。
- **幂等**：`SpawnPet` / `DespawnPet` / `Start` 重复调用安全。

## 边界（未改动）

`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `PlayerDataService` /
`MainUI` / `Net.lua` / `TaskConfig.lua` 均未改动。PetService **不**发放金币/经验/任务进度/奖励。
未新增任何客户端 RemoteEvent（宠物视觉通过 Anchored Part 的服务端 CFrame 自动复制）。

## 持久化：为什么宠物暂不持久化

- 本阶段起始宠物对**每位玩家隐式拥有**（加入即生成），无需存档，故**未改动 DataStore schema**。
- 真正的"宠物背包 + 拥有关系持久化"属于后续阶段（需要在 schema 增加 `Pets`/`EquippedPet` 字段并迁移）。

## 未来升级路径

- **Option B（宠物自身位置战斗）**：让宠物在**自己**靠近假人时攻击（主人可远离）。
  需要给 `DummyTargetService` 增加一个**附加**入口（例如 `ApplyHit({ creditPlayer, fromPosition })`），
  按宠物位置而非主人位置做距离校验。事件契约（`EnemyDefeated(player, enemyId)`）保持不变。
- **多宠物 / 宠物背包 / 升级 / 获取系统**：扩展 `PetConfig` 并在 schema 中持久化拥有关系。
- **性能**：当前跟随为服务端 Heartbeat 驱动；人数增多时可将"跟随"改为客户端表现、服务端只保留攻击判定。

> 核心循环总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)；假人机制见 [`Phase2-DummyTarget.md`](Phase2-DummyTarget.md)。
