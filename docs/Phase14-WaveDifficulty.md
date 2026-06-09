# Phase 14 — 分梯队波次难度 + Boss 里程碑（MVP）

> 把原本"每波固定 3 个 LagBlob、无难度曲线"替换为**分梯队**的塔防进程：
> 每 5 波为一个难度梯队，每第 5 波（5/10/15…）是 **Boss 波**。
> 仅实现系统地基，不加 Boss 技能 / 抗性 / 大型 VFX / 新美术 / 持久化。

## 1. Overview（概述）

难度全部**派生自 `waveNumber`**（确定性、可测试）。`WaveService.buildWavePlan(waveNumber)`
是一个纯函数，给出本波的敌人 id、数量与 hp/speed/reward **倍率**；倍率传给
`EnemyService.SpawnEnemy(enemyId, options)`，最终 `值 = EnemyConfig 基础值 × 倍率`。
Boss 复用现有敌人基础设施：一个新的配置项 `BossLagBlob`（更大体型 + 紫色 + 更高基础奖励），
Boss 波只刷 1 个 Boss，叠加随梯队增长的 Boss 倍率 → 更肉、更慢、奖励更高。

## 2. Player Fantasy（玩家体验）

每 5 波都是一个**里程碑**：前 4 波逐步加压，第 5 波出现一个明显更大、更肉、值钱的 Boss。
打过去就进入下一梯队，整体更难。早期 Boss 在合理布塔下可击败，给"我变强了"的正反馈。

## 3. Detailed Rules（规则）

- **梯队**：每 `WAVES_PER_TIER = 5` 波一个梯队。Tier 1 = 波 1–5，Tier 2 = 波 6–10，依此类推。
- **Boss 波**：`waveNumber % 5 == 0`（5/10/15/20…）。本波**只刷 1 个 Boss**，不刷普通怪。
- **普通波**：刷 `count` 个 `LagBlob`，数量与血量随梯队和梯队内序号增长，速度随梯队轻微增长。
- **结算不变**：击杀走 `onEnemyKilled` → 一次性发奖（`DamageEnemy` 的 `alive` 守卫保证不重发）；
  逃逸到达基地 → Base HP −1、**不发奖**（Boss 同样：逃逸不发奖）。Boss 奖励远高于普通怪。
- **重开兼容**：失败后按 R → `ResetSession` 把 `waveNumber` 归 0，难度派生自它，故所有梯队/Boss 状态随之清空；
  代号（generation token）保证重开后只有一个波次循环。

## 4. Formulas（公式）

```
tier        = floor((waveNumber - 1) / 5) + 1
waveInTier  = ((waveNumber - 1) % 5) + 1          -- 1..5；5 = Boss
isBossWave  = waveNumber % 5 == 0
```

**普通波**（基础敌人 `LagBlob`：hp 24 / speed 4 / reward 15）：
```
count       = 2 + waveInTier + tier
hpMult      = 1 + 0.20 * (tier - 1) + 0.08 * (waveInTier - 1)
speedMult   = 1 + 0.03 * (tier - 1)
rewardMult  = 1                                   -- 普通怪奖励不缩放
```

**Boss 波**（基础 Boss `BossLagBlob`：hp 30 / speed 4 / reward 18）：
```
count       = 1
hpMult      = 4 + 1.25 * tier
speedMult   = 0.75 + 0.03 * tier                  -- < 1 → 比普通怪慢
rewardMult  = 5 + tier
```

最终值：`finalHp = floor(baseHp * hpMult)`，`finalSpeed = baseSpeed * speedMult`，`finalReward = floor(baseReward * rewardMult)`。

### 示例表（按公式推导）

| Wave | Tier | 类型 | Count | HP×/怪 | Speed | Reward/怪 |
|-----:|:----:|:----|:-----:|:------|:-----:|:---------:|
| 1  | 1 | 普通 | 4 | ×1.00 → 24 | 4.00 | 15 |
| 2  | 1 | 普通 | 5 | ×1.08 → 25 | 4.00 | 15 |
| 3  | 1 | 普通 | 6 | ×1.16 → 27 | 4.00 | 15 |
| 4  | 1 | 普通 | 7 | ×1.24 → 29 | 4.00 | 15 |
| **5**  | **1** | **BOSS** | **1** | **×5.25 → 157** | **3.12** | **108** |
| 6  | 2 | 普通 | 5 | ×1.20 → 28 | 4.12 | 15 |
| 7  | 2 | 普通 | 6 | ×1.28 → 30 | 4.12 | 15 |
| 8  | 2 | 普通 | 7 | ×1.36 → 32 | 4.12 | 15 |
| 9  | 2 | 普通 | 8 | ×1.44 → 34 | 4.12 | 15 |
| **10** | **2** | **BOSS** | **1** | **×6.50 → 195** | **3.24** | **126** |
| 11 | 3 | 普通 | 6 | ×1.40 → 33 | 4.24 | 15 |
| **15** | **3** | **BOSS** | **1** | **×7.75 → 232** | **3.36** | **144** |

> Wave 5 Boss ≈ 5 个普通怪的血量、却是单目标，且奖励 108（普通 15 的 ~7×）。
> Wave 10 Boss 比 Wave 5 更肉（195 vs 157）→ "越后越强"。调参目标：单宠物 + 少量基础塔在合理布防下可击败早期 Boss。

## 5. Edge Cases（边界）

- **倍率非法**：`SpawnEnemy` 用 `posMult`（≤0 或非数字 → 回退 1），`maxHp` 至少 1、`reward` 至少 0。
- **Boss 逃逸**：与普通怪一致走 `OnEnemyEscaped` → Base HP −1、不发奖；不会因体型大而额外扣血。
- **受伤变色**：Boss 命中后与普通怪一样短暂变 `COLOR_HURT`（沿用现有逻辑）；Boss 仍可由**体型 + "Boss LagBlob" 标签**辨识。
- **重开期间**：`ResetSession` 先 `EnemyService.ClearAll()`（残余怪/Boss 置 `alive=false`，不再发奖/扣血），再归 0、重启循环；旧循环因代号变化退出，不会出现重复波次或旧 Boss 继续行动。
- **配置缺失**：若 `BossLagBlob` 缺失，`resolveDef` 回退到内置兜底敌人（不崩，仅失去 Boss 视觉）。

## 6. Dependencies（依赖）

- `EnemyService.SpawnEnemy(enemyId, options)` —— 新增 `options` 难度倍率 + 配置驱动 `size`/`color`/`isBoss`。
- `ReplicatedStorage/Config/EnemyConfig.lua` —— 新增 `BossLagBlob`。
- `EnemyService` 航点移动 / `DamageEnemy` 一次性守卫 / `GetAliveEnemies` / `ClearAll`（不变）。
- 击杀奖励通道 `ServerInit.onEnemyKilled`（不变）、`CombatService` / `TowerService`（**不变**）。

## 7. Tuning Knobs（可调参数）

- `WaveService`：`WAVES_PER_TIER`、`INTER_WAVE_DELAY_SECONDS`、`SPAWN_STAGGER_SECONDS`、`BASE_MAX_HP`、
  `NORMAL_ENEMY_ID`、`BOSS_ENEMY_ID`，以及 `buildWavePlan` 内的全部系数（数量/血量/速度/奖励曲线）。
- `EnemyConfig`：`LagBlob` 与 `BossLagBlob` 的 `health`/`speed`/`killReward`/`size`/`color`。

## 8. 未来可扩展（仅预留形状，Phase 14 不影响玩法）

`EnemyConfig` 的 Boss 项预留注释字段：`resistances` / `abilities` / `shapeVariant` / `skillSet`。
后续阶段可加入不同 Boss 形态、敌人技能、抗性与特效，无需改动本阶段的波次计划接口。

## 9. Acceptance Criteria（验收）

1. Wave 1 是简单普通波（少量弱怪）；Wave 2–4 逐步变难。
2. Wave 5 明显是 Boss 波：单个更大的 Boss、血量远高于普通怪、速度更慢。
3. Boss 沿 PathNodes 路径移动，可被宠物与塔伤害。
4. Boss 击杀发放一次更高奖励；Boss 逃逸扣基地血量且不发奖。
5. Wave 6 进入 Tier 2，比 Tier 1 普通波更难；Wave 10 Boss 比 Wave 5 更难。
6. 失败后按 R 重置回 Wave 1 / Tier 1；无重复波次循环、无旧怪/旧 Boss 残留行动。
7. 塔放置/塔攻击/宠物战斗、MainUI/Pet UI 均不受影响。

## 10. 安全与边界

- **不改** MainUI；**不改**受保护文件（DummyTargetService / GameEventService / TaskService / RewardService / TaskConfig.lua）；**不改** CombatService / TowerService。
- **不新增 remote**。难度与 Boss 全部服务端权威（客户端无法影响数量/血量/速度/奖励/Boss 状态）。
- **不改** DataStore：`PlayerData_v1` / `CURRENT_DATA_VERSION = 2`；不持久化波次/梯队进度。
