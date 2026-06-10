# Phase 16A — 玩家技能树：设计规格 + 数据模型规划

> **本阶段只做设计与脚手架**，不实现 UI、不消费技能点、不应用任何效果。
> 产出：(1) 本设计文档；(2) 纯数据脚手架 [`SkillTreeConfig.lua`](../src/ReplicatedStorage/Config/SkillTreeConfig.lua)
> （**不被任何 gameplay 代码 require**，故不影响玩法）。Phase 16B 才接入实现。

---

## 1. Overview（概述）

玩家用 Phase 15 攒下的 `SkillPoints` 在一棵**大而深**的技能树里投资，永久强化经济 / 防御塔 / 宠物 / 生存。
技能树分 **4 大分支**，每个节点可多级（`maxRank`），升级消耗技能点，部分节点有前置。
所有消费**服务端权威**：客户端只发"花费意图"，服务端校验点数 / 上限 / 前置后落库。
效果通过一个**集中的效果解析层**应用到既有系统（奖励结算 / 塔属性 / 宠物属性 / 基地血量）。

> 设计原则：**先窄后宽**。本阶段把 schema、持久化形状、效果 hook 点、消费规则全部定清楚，
> 让 Phase 16B 只需实现"3 个能跑通的技能 + 消费端点 + 极小 UI"，而不必返工架构。

## 2. Player Fantasy（玩家体验）

"我打得越久越强。" 每次升级攒的点数让玩家在多条 build 路线间做选择——
堆金币滚雪球、堆塔伤速推、养宠物单核、还是堆生存苟到更高波。深树带来长期目标与重复可玩性。

## 3. Skill Tree Categories（4 大分支）

| 分支 | 主题 | 效果 hook 点 |
|------|------|--------------|
| **Economy** | 金币 / 经验产出 | 奖励结算（`RewardService.GiveReward` / `ServerInit.onEnemyKilled`） |
| **Tower** | 防御塔强化 | 塔属性解析（`TowerService` 的 damage / range / attackInterval / cost） |
| **Pet** | 宠物强化 | 宠物属性解析（`PetService` / `CombatService` 的 damage / attackInterval；对 Boss 加成） |
| **Survival** | 基地与生存 | 基地血量逻辑（`WaveService` 的 `BASE_MAX_HP` 初始化 / `OnEnemyEscaped` 逃逸处理） |

## 4. Example Skills（MVP 初始节点）

下表与脚手架 [`SkillTreeConfig.Nodes`](../src/ReplicatedStorage/Config/SkillTreeConfig.lua) 一一对应。数值均为占位、可调。

### Economy
| id | 名称 | 每级效果 | maxRank | cost/级 | 前置 |
|----|------|----------|:------:|:------:|------|
| `eco_kill_coins` | Kill Coin Bonus | 击杀金币 +5% | 5 | 1 | — |
| `eco_xp_bonus` | XP Bonus | 击杀经验 +5% | 5 | 1 | — |
| `eco_boss_bounty` | Boss Bounty | Boss 奖励 +10% | 3 | 2 | `eco_kill_coins` r2 |

### Tower
| id | 名称 | 每级效果 | maxRank | cost/级 | 前置 |
|----|------|----------|:------:|:------:|------|
| `twr_damage` | Tower Damage | 塔伤害 +5% | 5 | 1 | — |
| `twr_range` | Tower Range | 塔射程 +3% | 5 | 1 | — |
| `twr_attack_speed` | Tower Attack Speed | 攻速 +3%（缩短间隔） | 5 | 1 | — |
| `twr_build_discount` | Build Discount | 建造花费 -2% | 5 | 1 | `twr_damage` r1 |

### Pet
| id | 名称 | 每级效果 | maxRank | cost/级 | 前置 |
|----|------|----------|:------:|:------:|------|
| `pet_damage` | Pet Damage | 宠物伤害 +5% | 5 | 1 | — |
| `pet_attack_speed` | Pet Attack Speed | 攻速 +3%（缩短间隔） | 5 | 1 | — |
| `pet_boss_hunter` | Boss Hunter | 对 Boss 伤害 +8% | 3 | 2 | `pet_damage` r2 |

### Survival
| id | 名称 | 每级效果 | maxRank | cost/级 | 前置 |
|----|------|----------|:------:|:------:|------|
| `sur_base_reinforce` | Base Reinforcement | 基地最大血量 +1 | 5 | 1 | — |
| `sur_leak_reduction` | Leak Reduction | 逃逸 10%/级 概率不扣血 | 3 | 2 | — |
| `sur_second_chance` | Second Chance | 每局一次：濒死改为 1 血存活（未来） | 1 | 3 | `sur_base_reinforce` r3 |

## 5. Node Schema（节点配置 schema）

每个节点字段（详见脚手架顶部注释）：

| 字段 | 类型 | 含义 |
|------|------|------|
| `id` | string | 唯一 id（`branchPrefix_name`） |
| `branch` | string | 所属分支（`Economy`/`Tower`/`Pet`/`Survival`） |
| `name` | string | 显示名 |
| `description` | string | 说明（含每级数值） |
| `maxRank` | number | 最大等级（rank 0..maxRank） |
| `costPerRank` | number | 升一级消耗的技能点（本阶段定值；未来可换 `costFormula(rank)`） |
| `prerequisites` | array | `{ { id, rank }, … }`，空表 = 无前置 |
| `effectType` | string | 效果类型，供效果解析层分发（见 §7） |
| `effectValuePerRank` | number | 每级效果增量（`0.05`=+5%/级；`1`=+1/级） |
| `appliesTo` | string | 作用对象（`reward`/`tower`/`pet`/`base`…），用于路由到正确 hook |
| `tags` | array | 可选，未来检索/分类 |

**未来可扩展字段**（本阶段仅预留，不实现）：`icon`、`uiPosition`（树状布局坐标）、`costFormula`、
`mutuallyExclusive`（互斥分支）、`respecRefundRatio`、`requiresPlayerLevel`。

## 6. Skill Point Spending Rules（消费规则 —— 设计，不实现）

服务端校验（Phase 16B 实现；客户端只发 `skillId` 意图）：

1. **节点存在**：`SkillTreeConfig.GetById(skillId)` 非空，否则拒绝（`unknown_skill`）。
2. **未满级**：`currentRank = SkillTree.Unlocked[skillId] or 0`；`currentRank < maxRank`，否则拒绝（`max_rank`）。
3. **前置满足**：对每个 `prerequisites[i]`，要求 `Unlocked[req.id] >= req.rank`，否则拒绝（`prereq`）。
4. **点数足够**：`cost = costPerRank`（下一级花费）；`SkillPoints >= cost`，否则拒绝（`not_enough_points`）。
5. **结算（成功）**：`SkillPoints -= cost`；`Unlocked[skillId] = currentRank + 1`；持久化 + 推送公开数据。

约定：
- `SkillPoints` 即"可用余额"（Phase 15 起每升级 +1；从未消费）。Phase 16B 起，消费从该余额扣减。
- **一次只升一级**（请求即"投 1 级到 skillId"）；连点由多次请求完成，便于审计与防作弊。
- 所有数值（rank/cost）由服务端依据配置计算，**绝不信任客户端传入的 rank/cost**。

## 7. Effect Architecture（效果应用架构 —— 设计，不实现）

引入一个集中的 **`SkillEffectResolver`**（Phase 16B 新增，服务端）：输入玩家的 `SkillTree.Unlocked`，
输出聚合后的修正系数；各系统在"解析属性/结算"的位置调用它，**保持单向依赖、服务端权威**。

建议接口（草案）：
```
SkillEffectResolver.GetMultiplier(player, effectType) -> number   -- 聚合所有相关节点：1 + Σ(rank * valuePerRank)
SkillEffectResolver.GetFlat(player, effectType)       -> number   -- 平铺加成：Σ(rank * valuePerRank)
SkillEffectResolver.Has(player, effectType)           -> boolean  -- 是否拥有某 1 级效果（如 second_chance）
```

各分支 hook 点（**仅标注位置，本阶段不改这些文件**）：

| 分支 | effectType | hook 位置 | 应用方式 |
|------|-----------|-----------|----------|
| Economy | `coin_mult` / `xp_mult` | `RewardService.GiveReward` 或 `ServerInit.onEnemyKilled` 构造 reward 处 | `coins = floor(coins * GetMultiplier(coin_mult))`，XP 同理 |
| Economy | `boss_reward_mult` | 同上，仅当 `enemy.isBoss` | 再乘一层 boss 系数 |
| Tower | `tower_damage_mult` / `tower_range_mult` / `tower_attackspeed_mult` | `TowerService` 解析每塔 `damage/range/attackInterval` 处 | damage/range ×系数；attackInterval ÷ 攻速系数 |
| Tower | `tower_cost_mult` | `TowerService.TryPlaceTower` 计算 cost 处 | `cost = ceil(cost * (1 - GetFlat(tower_cost_mult)))`，下限保护 |
| Pet | `pet_damage_mult` / `pet_attackspeed_mult` | `PetService`/`CombatService` 解析宠物 `attackDamage/attackInterval` 处 | 同塔逻辑 |
| Pet | `pet_damage_vs_boss_mult` | 宠物对敌伤害结算、目标 `isBoss` 时 | 命中 Boss 再乘一层 |
| Survival | `base_max_hp_flat` | `WaveService` 初始化 `BASE_MAX_HP` / 会话重置处 | `maxHp = BASE_MAX_HP + GetFlat(base_max_hp_flat)` |
| Survival | `leak_ignore_chance` | `WaveService.OnEnemyEscaped` 扣血前 | 概率跳过这次 -1（确定性测试需可注入随机源） |
| Survival | `survive_once_per_run` | `WaveService` Base HP 归 0 判定处 | 每局一次改为存活 1 血（需 per-run 标记） |

要点：
- 效果对**当前会话**生效；技能等级**持久**（玩家进度），但每局战斗状态不持久（与 Phase 13/14 一致）。
- `leak_ignore_chance` 含随机：为满足"确定性测试"，随机源应可注入（测试用固定种子/桩）。
- 这些 hook 不新增跨域依赖：各系统**调用** Resolver，Resolver 只读玩家数据 + 配置。

## 8. Persistence Design（持久化设计 —— 本阶段不落库）

提议在玩家数据中新增：
```lua
SkillTree = {
  Unlocked = { [skillId] = rank, ... },   -- 仅存"已投等级"；未出现的 = 0
},
SkillTreeVersion = 1,                       -- 独立迁移标记（仿 Phase 15 的 ProgressionVersion）
```

迁移与版本（**Phase 16B 执行，本阶段不做**）：
- 新增持久字段时：`CURRENT_DATA_VERSION` 3 → 4；并用**独立**的 `SkillTreeVersion` 标记技能树是否已初始化
  （沿用 Phase 15 教训：不要只靠 `DataVersion` 判断子系统是否初始化）。
- 迁移：缺失 `SkillTree` → 补 `{ Unlocked = {} }`、`SkillTreeVersion = 1`；不动 `SkillPoints/Level/XP/Coins/Pets`。
- `reconcile` 需校验 `Unlocked`：丢弃未知 `skillId`、把 rank clamp 到 `[0, maxRank]`（防篡改/配置收缩）。
- **本阶段不改 `PlayerDataService`、不 bump `DataVersion`**（无新持久字段）。

## 9. Edge Cases（边界 —— 供 16B 落地时遵循）

- 配置收缩/改名：加载旧存档时丢弃未知 `skillId`、clamp 超出的 rank（避免"幽灵技能"）。
- `costPerRank` 改动后：已投等级不追溯退点（除非做 respec，本阶段不做）。
- 前置被"反悔"：本阶段无 respec，故前置一旦满足不会失效；未来 respec 需做依赖回滚校验。
- 重开（R）：只重置 wave/base/塔/敌人；技能等级与点数**不重置**（属玩家长期进度）。
- 并发花费：服务端按单请求顺序处理，校验后再扣点，避免超额消费。

## 10. Dependencies（依赖）

- **现状**：仅新增纯数据 `SkillTreeConfig.lua`，无人 require → 零运行时依赖、零玩法影响。
- **Phase 16B 将依赖**：`PlayerDataService`（持久 `SkillTree`、消费 `SkillPoints`）、新 `SkillEffectResolver`、
  以及在 `RewardService` / `TowerService` / `PetService`-`CombatService` / `WaveService` 各加 1 处 hook。
- 受保护文件（DummyTargetService / GameEventService / TaskService / TaskConfig.lua）**不涉及**。

## 11. Tuning Knobs（可调参数）

`SkillTreeConfig` 内每个节点的 `maxRank` / `costPerRank` / `effectValuePerRank` / `prerequisites`；
分支数量与节点集合；未来的 `costFormula`、`requiresPlayerLevel`。鉴于 XP 曲线陡（`100*level^2`），
点数稀缺，早期数值宜保守（5%/3% 量级），避免滚雪球过快。

## 12. Acceptance Criteria（本设计阶段的验收）

1. 文档定义了 4 大分支、各分支 MVP 节点、完整节点 schema、消费规则、效果架构、持久化形状、16B 建议。
2. `SkillTreeConfig.lua` 为纯数据 + 只读查询，**不被任何 gameplay 代码 require**，不改玩法。
3. **未改** `PlayerDataService`、**未** bump `DataVersion`、**未改** MainUI、**未碰**受保护文件。
4. 工程可正常构建（JSON 合法；新配置文件可被 Rojo 纳入但当前无人加载）。

---

## 13. MVP Implementation Recommendation — Phase 16B（建议先做什么）

**目标：用最小闭环验证"花点数 → 持久化 → 效果生效"，只上 3 个技能。**

1. **最小配置**：沿用本脚手架，但 16B 先只"启用"**前 3 个最具代表性、各占一分支**的节点：
   - `eco_kill_coins`（Economy，钩奖励）
   - `twr_damage`（Tower，钩塔属性）
   - `pet_damage`（Pet，钩宠物属性）
   （Survival 的 `base_max_hp_flat` 可作为第 4 个"拉伸目标"，因它最易测：开局看 Base HP 上限变化。）
2. **持久化**：`PlayerDataService` 加 `SkillTree = { Unlocked = {} }` + `SkillTreeVersion = 1`；
   `CURRENT_DATA_VERSION` 3 → 4；reconcile 做未知 id 丢弃 + rank clamp（仿 Phase 15 迁移与 marker 模式）。
3. **服务端消费端点**：新增最小 `SkillRemote`：C→S `"Spend", skillId`（仅意图）；
   S→C `"Result", { success, reason, skillId, rank }` 与 `"Update", skillTreePublic`。全部校验在服务端（§6）。
4. **效果解析层**：新增 `SkillEffectResolver`，先只实现这 3 个 `effectType` 的聚合；在对应 hook 各加 1 行乘法。
5. **极小 UI / 命令**：二选一——
   - 一个独立 ScreenGui 小面板（仿 Phase 13 `RunControl` 风格，**不改 MainUI**）列出 3 个技能 + 升级按钮；或
   - 一个 QA 用聊天命令 / 调试键，触发 `Spend`，用 Output 日志 + 现有 HUD 的 SkillPoints 数字验证。
6. **验收**：花 1 点 → SkillPoints -1、对应技能 rank+1、效果在下次结算/属性解析中可量化体现；重开不重置；重进保留。

**之后（16C+）**：补齐其余节点与分支、前置连线的真正树状 UI、Survival 随机/濒死效果（含可注入随机源的确定性测试）、
respec（退点）等。**仍不做**：宠物独立技能树、付费技能点、shop/gacha。
