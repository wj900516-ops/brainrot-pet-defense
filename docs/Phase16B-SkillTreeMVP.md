# Phase 16B — 玩家技能树：最小可用实现（MVP）

> 打通技能树的第一个闭环：**持久化技能等级 → 服务端权威消费 → 缓存修正量 → 3 个生效的技能效果**。
> 仅实现 3 个技能（`eco_kill_coins` / `twr_damage` / `pet_damage`），不做完整树 UI / 全部效果 / respec / 宠物树。
> 基于 Phase 16A 的设计与 [`SkillTreeConfig.lua`](../src/ReplicatedStorage/Config/SkillTreeConfig.lua)。

## 1. Overview（概述）

- **持久化**：玩家数据新增 `SkillTree = { Version = 1, Unlocked = { [skillId] = rank } }`。只存按 id 的等级；
  branch/total 等派生量**动态计算**，不落库。`CURRENT_DATA_VERSION` 3 → 4（`DATASTORE_NAME` 不变）。
- **服务端权威消费**：`SkillTreeService.TrySpend(player, skillId)` 做全部校验 + 扣点 + 升级；客户端只发意图。
- **缓存修正量**：`SkillEffectResolver` 把已投等级聚合成 per-player 缓存；攻击/结算时 O(1) 读取，不每帧遍历树。
- **3 个效果**：击杀金币 +5%/级、塔伤害 +5%/级、宠物伤害 +5%/级（均服务端施加）。

## 2. Persistence & Migration（持久化与迁移，v3 → v4）

- `defaultData` 含 `SkillTree = { Version = 1, Unlocked = {} }`。新玩家直接得空树。
- `reconcile`（v3 → v4）：v3 存档无 `SkillTree` → 用默认；保留 `Coins / Level / XP / SkillPoints / ProgressionVersion / 宠物 / 装备 / 任务 / 设置`。**不 wipe**。
  - `PlayerDataService` 只做**结构性清洗**：保留 `Version` 与 `Unlocked`（仅 `string` 键 + 正整数 rank）。
  - **配置感知清洗**（丢弃未知 `skillId`、按 `maxRank` 夹紧）由 `SkillTreeService.SanitizeOnLoad` 在加载后完成
    （`PlayerDataService` 是最底层，不依赖 `SkillTreeConfig`）。
- `SkillTree.Version` 为独立迁移标记（仿 Phase 15 的 `ProgressionVersion`），便于将来技能树独立迁移。
- **未知技能丢弃不退点**：Phase 16B 无历史技能树数据，丢弃是安全的；若未来配置删节点，应改为退点（见 §10）。

## 3. Server Services（服务端服务）

### SkillTreeService（`src/ServerScriptService/Services/SkillTreeService.lua`）
- `SanitizeOnLoad(player)`：配置感知清洗（丢弃未知、夹紧 rank）。
- `GetTotalPoints(player)` / `GetBranchPoints(player, branch)`：从 `Unlocked` + 配置**动态算点**。
- `TrySpend(player, skillId)`：去抖/锁 + 全部校验 + 扣点 + 升级 + 通知 `SkillEffectResolver.Rebuild`。
- `GetPublicState(player)`：返回 `{ skillPoints, totalPoints, unlocked, skills=[启用技能精简信息] }`（拷贝/精简，不暴露可变内部表）。
- `ClearPlayer(player)`：清去抖/锁。

### SkillEffectResolver（`src/ServerScriptService/Services/SkillEffectResolver.lua`）
- `Rebuild(player)` / `Clear(player)`：在玩家加载、成功消费、（未来）respec 时重建；玩家离开时清除。**不在攻击热路径重建**。
- `GetNumber(player, modifierKey, default?)` / `GetFlag(player, modifierKey)`：O(1) 读缓存（攻击/结算用）。
- `ResolveStat(base, opts)` / `Clamp(...)` / `ApplyCostReduction(...)`：通用 stat 解析 + 夹紧（见 §5）。

## 4. Spend Validation（消费校验，服务端）

`SkillTreeService.TrySpend` 顺序（任一不过即安全拒绝并返回 `reason`）：
1. `skillId` 为非空字符串，否则 `bad_request`。
2. 去抖/锁：处理中 → `busy`；距上次 < 0.2s → `too_fast`。
3. 节点存在（`SkillTreeConfig.GetById`），否则 `unknown_skill`。
4. **Phase 16B allowlist**：仅 `eco_kill_coins` / `twr_damage` / `pet_damage` 可消费，否则 `not_implemented`。
5. `currentRank < maxRank`，否则 `max_rank`。
6. `costPerRank` 合法（>0 整数），否则 `bad_cost`。
7. `SkillPoints >= cost`，否则 `not_enough_points`。
8. 前置节点 `requirements.prerequisiteNodes` 全部满足，否则 `prereq_node`。
9. `branchPoints >= requiredBranchPoints`，否则 `prereq_branch`。
10. `totalPoints >= requiredTotalPoints`，否则 `prereq_total`。
11. 通过 → `AddSkillPoints(-cost)` → `SetSkillRank(rank+1)` → `Rebuild`。

**客户端绝不可发送** rank / cost / branchPoints / totalPoints / modifiers / 伤害 / 奖励 —— 这些全部服务端计算。
每次消费都**重新校验当前数据**，因此即使绕过去抖也无法使 `SkillPoints` 变负或 rank 超 `maxRank`。

## 5. Modifier Math & Clamp（修正量次序与夹紧）

严格次序（`SkillEffectResolver.ResolveStat`）：
```
Base → flat add → additive percent → multiplicative percent → clamp
```
支持的 `applyMethod`：`flat`（平铺加）/ `additive`（百分比相加）/ `multiplicative`（各 ×(1+v)）/ `flag`（布尔）。
聚合后 `GetNumber(key)` 返回该 key 的单一修正量 delta（百分比类 → 消费方 `base*(1+delta)`；平铺类 → `base+delta`）。

夹紧规则（架构已就位；Phase 16B 的 3 个技能未触发）：
- **花费折扣**永不低于基础花费的 **20%**（`ApplyCostReduction`）。
- 攻击间隔/冷却的缩减将来实现时不得低于安全下限（占位规则，本阶段未涉及）。
- 通用 `Clamp(value, min, max)` 可用于任意 stat。

## 6. 三个效果实现

| 技能 | ModifierKey | hook | 施加方式 |
|------|-------------|------|----------|
| `eco_kill_coins` | `CoinMultiplier` | `ServerInit.onEnemyKilled` | `coins = round(baseCoins * (1 + bonus))`（普通+Boss 击杀；逃逸不进此路径） |
| `twr_damage` | `TowerDamageMultiplier` | `TowerService` 攻击循环 | `dmg = baseDamage * (1 + bonus)`（浮点精确） |
| `pet_damage` | `PetDamageMultiplier` | `CombatService` 攻击循环 | `dmg = baseDamage * (1 + bonus)`（浮点精确） |

- **金币取整为四舍五入**（`floor(x+0.5)`），使低基数下 rank 1 也有可见 +5%（如 15 → 16）。
- **伤害用浮点**（敌人 hp 为浮点，`DamageEnemy` 接受浮点），避免对小整数（塔 8 / 宠物 15）取整抹掉低级加成。
- 击杀奖励仍**一次性**（`EnemyService.DamageEnemy` 的 `alive` 守卫）；宠物/塔击同一敌人不重复发奖。
- 三者均**服务端施加**，客户端无法影响伤害/奖励。

## 7. SkillRemote（最小远程）

`SkillRemote`（新增）：
- C→S `"RequestState"` → 回推技能树状态。
- C→S `"SpendPoint", skillId` → 仅意图；服务端 `TrySpend` 校验后结算。
- S→C `"State", publicSkillTreeState` → `{ skillPoints, totalPoints, unlocked, skills }`（加入时主动推一次）。
- S→C `"Result", { success, reason, skillId?, rank?, skillPoints? }` → 成功/失败都回推。

成功消费后服务端同时 `pushData`（刷新 MainUI 技能点数字）与 `pushSkillState`（刷新调试 UI）。

## 8. Debounce / Lock（去抖 / 锁）

`SkillTreeService` 内每玩家：
- **处理锁** `spendLock[player]`：处理中再来 → `busy`（防 `doSpend` 万一 yield 的重入）。
- **时间去抖** 0.2s：距上次处理 < 0.2s → `too_fast`。
- 双重保险之外，**每次消费都重新校验**当前点数/rank，从根本上保证：点数不会变负、rank 不会超 `maxRank`、同一点不会被双花。

## 9. UI（最小调试界面）

`SkillTreeDebug`（`src/StarterGui/SkillTreeDebug/SkillTreeDebug.client.lua`）：**独立 ScreenGui，右上角**，**不改 MainUI**。
- 显示 `Skill Points` 与 3 个启用技能的 `rank/maxRank (cost)` 与 `[+]` 按钮。
- 按钮在 `已满级` 或 `点数不足` 时禁用（显示门槛）；点击只发 `SpendPoint` 意图。
- 服务端拒绝时显示小 `Rejected: <reason>` toast。
- 客户端从不发送 rank/cost/点数；一切由服务端裁决。

## 10. Sanitization & Edge Cases

- 加载：未知 `skillId` 丢弃（不退点，已记录日志）；rank 夹到 `[0, maxRank]`；非法类型规范化；派生点数动态重算。
- 非启用技能：配置可见但 `TrySpend` 返回 `not_implemented`，UI 也不列出（只列 3 个启用技能）。
- 并发：单请求顺序处理 + 去抖；先扣点再写 rank。
- **未来若删除配置节点**：应改为"退点"策略并文档化；Phase 16B 因无历史数据，安全丢弃即可。

## 11. Restart / Session 兼容

按 R 重开只重置 `enemies / towers / base / waves`（`WaveService.ResetSession` + `TowerService.ClearAll`），
**不**触碰玩家进度或技能树：`SkillPoints / SkillTree ranks / 缓存修正量 / XP / Level` 全部保留（缓存只在玩家离开时清）。

## 12. Files（改动文件）

- 新增：`SkillTreeService.lua`、`SkillEffectResolver.lua`、`SkillTreeDebug/SkillTreeDebug.client.lua`、本文档。
- 修改：`PlayerDataService.lua`（v4 + SkillTree + 访问 API）、`ServerInit.server.lua`（接线 + 金币效果 + remote）、
  `TowerService.lua`（塔伤害效果）、`CombatService.lua`（宠物伤害效果）、`Net.lua`（SkillRemote）、`MVP-Core-Loop.md`。
- **未改**受保护文件（DummyTargetService / GameEventService / TaskService / TaskConfig.lua）与 `MainUI.client.lua`、`RewardService.lua`。

## 13. Acceptance Criteria（验收）

1. v3 → v4 安全迁移；Coins/Pets/装备/XP/Level/SkillPoints 保留；`SkillTree` 默认 `{ Version=1, Unlocked={} }`。
2. 可消费 `eco_kill_coins` / `twr_damage` / `pet_damage`：rank +1、`SkillPoints` 减 cost。
3. 击杀金币 +5%/级（普通+Boss）；塔/宠物伤害 +5%/级；逃逸不发奖；奖励一次性。
4. 点数不足 / 满级 / 非启用技能 → 安全拒绝并显示 reason。
5. 双击/宏不会重复扣点、点数不变负、rank 不超 maxRank。
6. 重开（R）不重置技能等级 / 修正量 / 点数 / 等级经验。

## 14. Known Limitations（已知限制）

- 仅 3 个技能启用；其余节点配置可见但 `not_implemented`。
- 无完整技能树 UI、无 respec、无宠物技能树、无 Defense/Keystone 效果。
- 伤害效果以浮点施加，敌人 HP 标签按整数显示，单次掉血的可见数字可能与精确值有 ±1 的取整差。
- 未知技能丢弃不退点（Phase 16B 无历史数据，安全）。
