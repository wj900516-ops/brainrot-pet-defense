# Phase 9 — Wave Progression + Base HP / Lose Condition MVP

> 目标：把战斗循环变成真正的"防御循环"——
> 敌人成波到来；逃到基地会扣基地血量；基地血量归 0 → 会话失败。
> server-authoritative、最小可行、不持久化。

## 会话循环

```
WaveService.Start（后台循环，sessionFailed 时停止）
  waveNumber += 1
  → 生成 ENEMIES_PER_WAVE 个 LagBlob（轻微错峰）
  → 等待本波全部"解决"（击杀或逃逸 → 无存活敌人）
  → 延迟 INTER_WAVE_DELAY_SECONDS → 下一波

敌人击杀（CombatService → DamageEnemy 致命一击）
  → ServerInit.onEnemyKilled → RewardService 发奖励 + 反馈（Phase 8/8.5，未改动）

敌人逃逸（EnemyService 移动到达基地）
  → EnemyService.onEscaped → WaveService.OnEnemyEscaped
      → Base HP -1（逃逸【不】发奖励）
      → Base HP == 0 → sessionFailed = true → 停止刷怪 + EnemyService.ClearAll()
```

## 波次进程（Wave progression）

- `waveNumber` 服务端状态，从 1 开始。
- 每波固定 `ENEMIES_PER_WAVE = 3` 个 `LagBlob`（**无 Boss / 精英 / 新敌人类型 / 难度曲线**）。
- 本波"解决"判定：生成完后轮询 `EnemyService.GetAliveEnemies()`，归 0 即本波结束（击杀与逃逸都会从存活列表移除）。
- 本波结束后延迟 `INTER_WAVE_DELAY_SECONDS = 5` 开始下一波。
- 每个敌人最终必然被"击杀或逃逸"解决（始终朝基地移动），不会无限等待。

## 基地血量（Base HP）

- `baseHp` 服务端状态，初始 `BASE_MAX_HP = 10`。
- 敌人到达基地（逃逸）→ `baseHp -= 1`（`math.max(0, ...)` 永不低于 0）。
- **逃逸不发奖励**：奖励只发生在击杀路径（`onEnemyKilled`），逃逸路径（`onEscaped`）只扣血。
- 击杀与逃逸互斥：敌人的 `alive` 一次性置 false（DamageEnemy / 逃逸 谁先到谁生效），
  因此**同一敌人不会既发奖励又扣基地血量**，也不会重复扣血/重复发奖。

## 失败条件（Lose condition）

- `baseHp` 归 0 → `sessionFailed = true`。
- 失败后：波次循环停止刷怪；`EnemyService.ClearAll()` 清理残余敌人。
- **本 MVP 无重开 UI**：开新会话请重新 Play Solo（可接受）。

## 可见性（QA visibility）

WaveService 在基地处创建一块**世界状态板**（服务端 `Part` + `BillboardGui`，自动复制）：

- 正常：`Wave N   |   Base HP X/10`
- 失败：`BASE DESTROYED  —  reached Wave N`（红色）

并辅以服务端日志：波次开始/结束、逃逸扣血、会话失败。

> **未改动 MainUI**、**未新增 remote**。状态板是世界对象（与敌人/宠物的 Billboard 同类），非客户端 UI 重设计。

## 架构 / 边界

- **扩展既有** `WaveService`（现承载会话状态：waveNumber/baseHp/sessionFailed + 波次循环 + 基地状态板）
  与 `EnemyService`（新增只读式 `ClearAll()`）。
- `CombatService` **未改动**（仍只做伤害判定 + 击杀回调）。
- 奖励仍走既有 `RewardService`（**未改动 RewardService**）。
- server-authoritative：客户端无法伪造波次进度 / 基地伤害 / 奖励 / 失败状态（无客户端变更 remote）。
- **未改动**受保护文件：`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `TaskConfig.lua` / `MainUI.client.lua`。
- **未改动** DataStore：`PlayerData_v1` / `CURRENT_DATA_VERSION = 2`；波次/会话/基地血量**不持久化**（仅内存，重进重置）。

## 可调参数（WaveService 顶部）

| 参数 | 默认 | 含义 |
|------|------|------|
| `ENEMIES_PER_WAVE` | 3 | 每波敌人数 |
| `INTER_WAVE_DELAY_SECONDS` | 5 | 两波间延迟 |
| `SPAWN_STAGGER_SECONDS` | 1 | 同波内生成间隔 |
| `BASE_MAX_HP` | 10 | 基地初始血量 |

## 范围外（Out of Scope）

- 商店 / 抽卡 / 新宠物 / 新敌人 / Boss / 寻路 / 付费 / 排行榜。
- 持久化波次进度（本阶段会话状态仅内存）。
- 重开 UI、大型 UI 重设计。

## 已知限制

- 失败后需重新 Play Solo 开新会话（无重开按钮）。
- 基地状态板为世界 Billboard；若玩家走太远可能需要靠近基地查看。
- 波次为固定数量/固定节奏，无难度曲线（刻意保持简单）。
- 逃逸判定依赖敌人持续朝基地移动（CanCollide=false，玩家无法阻挡）。

> 战斗与奖励见 [`Phase8-CombatLoop.md`](Phase8-CombatLoop.md)；核心循环总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
