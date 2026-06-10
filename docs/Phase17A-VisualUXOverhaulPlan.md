# Phase 17A — 视觉 / UX 大改造：规划与架构规范

> **本阶段只做规划与规范文档**，不改任何 gameplay 代码、不动 DataStore、不加 remote、不做新美术/地图/模型。
> 目标：为后续 17B/18/19/20 的视觉、UI、模型、地图改造定下"在不破坏服务端权威核心的前提下替换外观"的规则。

## 0. Roadmap（已批准路线）

| 阶段 | 主题 |
|------|------|
| **17A**（本文档） | 视觉 / UX 改造规划 |
| 17B | 地图 + PathNodes 资产规则 |
| 18 | 新塔类型 / 技能树解锁塔 |
| 19 | 宠物技能树 / 宠物能力解锁 |
| 20 | 完整 UI / 美术大改 |

**核心原则（贯穿全程）**：**外观可换，权威不动。** 视觉是"皮"，服务端规则是"骨"。任何改造先问：
"这会改变服务端的判定/数值/状态吗？" 若会 → 它是 gameplay 改动，走设计+实现+QA 流程，不属于"纯视觉"。

---

## 1. Protected Gameplay Core（受保护的玩法核心）

以下系统是服务端权威核心。**视觉/UI 工作不得随意重写其逻辑/契约**；如需改其行为，必须作为独立的 gameplay
阶段、带设计文档与 QA，而非夹带在视觉改造里。

| 系统 | 文件 | 拥有的权威 |
|------|------|-----------|
| 玩家数据 | `PlayerDataService.lua` | 持久化 schema、Coins/Level/XP/SkillPoints/SkillTree、DataStore 读写与迁移 |
| 奖励 | `RewardService.lua` | 金币/经验发放、升级 + 技能点结算的结果结构 |
| 敌人 | `EnemyService.lua` | 生成 / 航点移动 / 受伤 / 死亡 / 逃逸；`DamageEnemy` 的一次性击杀守卫 |
| 波次/会话 | `WaveService.lua` | 波次进程、梯队/Boss 计划、基地血量、失败、重开（generation token） |
| 塔 | `TowerService.lua` | 放置校验（金币/距路径/距塔/位置）、自动攻击、击杀回调 |
| 宠物 | `PetService.lua` | 装备/生成/跟随、`GetActivePet` |
| 战斗 | `CombatService.lua` | 宠物→敌人伤害判定、击杀回调 |
| 技能树 | `SkillTreeService.lua` | 消费校验（去抖+锁+点数/上限/前置/allowlist）、动态算点 |
| 技能效果 | `SkillEffectResolver.lua` | 已投等级→缓存修正量；严格修正次序 + 夹紧 |
| 网络 | `Net.lua` | RemoteEvent 协议（action 字符串 + 负载），全部 intent-only |

**红线**：不在视觉阶段更改上述任一文件的"判定/数值/状态/契约"。允许的接触仅限**显式的、向后兼容的**
扩展（如给 config 增加 `modelId` 字段并由服务端忽略、由客户端读取）——且需在对应阶段说明。

## 2. Visual Replacement Principles（视觉替换原则）

美术 / 模型 / UI 可以替换，**当且仅当**全部满足：

1. **服务端规则保持权威**：伤害/范围/花费/奖励/波次/基地血量/技能效果一律由服务端计算，绝不信任客户端。
2. **Remote 保持 intent-only**：客户端只发"意图"（如 `PlaceTower` / `SpendPoint(skillId)` / `Restart`），
   绝不发送 rank/cost/modifiers/damage/reward/position-as-truth（位置仍由服务端校验）。
3. **DataStore schema 不动**：不改 `DATASTORE_NAME`、不 bump `CURRENT_DATA_VERSION`，除非有**显式迁移**
   （沿用既有教训：用独立子系统版本标记如 `ProgressionVersion` / `SkillTree.Version`，并保留旧字段、补默认、丢未知）。
4. **模型名 / 配置 ID 稳定或谨慎迁移**：`skillId` / `petId` / `towerId` / `enemyId` / 航点命名等是数据契约；
   改名等同迁移，需保证旧存档/旧引用安全（丢弃未知要文档化是否退点/兼容）。

> 判定口诀：**"能不能在不碰 §1 任一文件的判定逻辑的情况下完成？"** 能 → 纯视觉，放心做；不能 → 它是 gameplay。

## 3. Map Overhaul Rules（地图改造规则）

未来换地图的硬性要求（`EnemyService` 已实现的解析契约，不要打破）：

- **敌人路线 = `Workspace.PathNodes`**（解析顺序：先 `EnemyPath`，再 `PathNodes`；都无效则兜底直线）。
- 文件夹下的 **BasePart 子物体即航点**，需 **≥ 2 个**。
- **第一个航点 = 出生点**；**最后一个航点 = 基地**（基地状态板与逃逸判定都基于它）。
- **节点顺序 = 自然数字顺序**（末尾数字升序：`Node1 < Node2 < … < Node10`；无数字者退名称排序并排在后）。
- **地图美术不可作为路径事实**：敌人只沿 PathNodes 走。换地图时**PathNodes 必须与可见道路对齐**，否则敌人会"穿模"或走错。
- 航点可不可见（`Transparency=1` / `CanCollide=false` / `CanQuery=false`）；可保留或重新生成，但必须维持上述契约。
- 塔放置的"距路径过近"用的是 PathNodes 折线（逐段 XZ 距离），换路必然影响可建区——这是预期行为。

## 4. Tower Visual Rules（塔：视觉与逻辑分离）

- **`TowerConfig` 拥有玩法数值**：`cost / range / damage / attackInterval / size`（以及未来 `modelId`）。
- **`TowerService` 拥有放置/战斗**：校验、扣币、攻击循环、击杀回调；伤害修正经 `SkillEffectResolver`（如 `twr_damage`）。
- **未来塔模型由 config 引用**（见 §8）：换模型 = 改 `TowerConfig.modelId`，**不改 TowerService**。
- **换塔外观不得改伤害/范围/花费**，除非 config 数值随之改动并走平衡评审。视觉与数值解耦。

## 5. Pet Visual Rules（宠物：视觉与逻辑分离）

- **`PetConfig` 拥有宠物数值**：`attackRange / attackDamage / attackInterval / followOffset`（以及未来 `modelId`）。
- **`PetService` 拥有装备/生成/跟随**；**`CombatService` 拥有宠物攻击判定**（伤害修正经 `SkillEffectResolver`，如 `pet_damage`）。
- **未来宠物模型/动画不得改变战斗权威**：动画只是表现；命中/伤害/间隔仍由服务端按 config + 修正计算。
- 新宠物 = 新 `PetConfig` 条目（稳定 `petId`）+ 未来 `modelId`；装备/库存仍走 `PlayerDataService` 既有数据契约。

## 6. Enemy Visual Rules（敌人：视觉与逻辑分离）

- **`EnemyConfig` 拥有敌人数值**：`health / speed / killReward / xpReward / baseDamage`，以及视觉 `size / color`（未来 `modelId`）。
- **`EnemyService` 拥有生成/移动/受伤/逃逸**；难度倍率由 `WaveService.buildWavePlan` 计算后经 `SpawnEnemy(id, options)` 施加。
- **未来敌人形状/颜色/模型/动画可换**：纯表现，不改移动/受伤/奖励判定。
- **Boss 技能 / 抗性是未来 gameplay 特性，不是"纯视觉"**：它们改变战斗判定，必须走 gameplay 阶段（设计+实现+QA），
  并落到 config 的预留字段（`resistances / abilities / shapeVariant / skillSet`，见 Phase 16A 设计预留）。

## 7. Skill Tree UI Rules（技能树 UI 规则）

- **`SkillTreeConfig` 是技能定义的唯一来源**（分支/节点/`modifiers`/`requirements`/`maxRank`/`costPerRank`/`ui`）。
- **`SkillTreeService` 校验消费**（服务端权威）；**`SkillEffectResolver` 计算效果**（缓存修正量）。
- **UI 可完全重设计**，只要它：
  - 仅向服务端发送 `SpendPoint(skillId)`（与只读 `RequestState`）意图；
  - **绝不**发送 rank / cost / branchPoints / totalPoints / modifiers / 伤害 / 奖励；
  - 静态展示信息（名称/说明/花费/上限）可客户端读 `SkillTreeConfig`，但**可消费与否、等级、点数以服务端 `State` 为准**。
- 未来连线树状图 / 图标 / 动画都属于 UI 层，不触碰 §1 任一服务。

## 8. Future Asset / Config Mapping Proposal（未来字段提案，先不实现）

提议未来给配置增加"资产引用"字段，使**换模型/图标 = 改数据，不改逻辑**。本阶段**不实现**（除非已是 trivial 且 inert）：

| 配置 | 提议字段 | 含义 |
|------|---------|------|
| `TowerConfig` | `modelId` / `modelName` | 塔模型资产（Workspace/ReplicatedStorage 下的模板名或资产 id） |
| `PetConfig` | `modelId` / `modelName` | 宠物模型资产 |
| `EnemyConfig` | `modelId` / `modelName` | 敌人模型资产（缺失则回退现有占位 Part + `size`/`color`） |
| `SkillTreeConfig.ui` | `icon`（已存在占位空串） | 技能图标资产 id（已在 16A schema 预留，当前为 `""`） |

落地原则（未来阶段）：
- 字段**可选**：缺失时回退到现有占位渲染（不崩、不改玩法）。
- 服务端**忽略**这些纯视觉字段（除非需要服务端生成模型——届时仍只读 config，不改判定）。
- 资产模板放在约定文件夹（见 §9），按 `modelId` 解析；解析失败回退占位。

## 9. Phase 17B Proposal（下一阶段：地图 + PathNodes 资产规则）

Phase 17B 建议产出（仍以规范 + 轻量工具为主，不改玩法判定）：

1. **形式化 PathNodes**：固化文件夹名（`PathNodes` 优先）、航点命名（`Node1..N` 自然数字序）、最少节点数、首=spawn/末=base 约定。
2. **命名规范**：航点 / 塔模板 / 宠物模板 / 敌人模板 / 资产文件夹的统一命名表。
3. **调试可视化**：可选的"航点连线 + 序号 + 出生/基地标记"调试绘制（客户端或编辑期工具，默认关闭，不影响玩法）。
4. **地图 QA 清单**：换图后必查项（PathNodes ≥2、顺序正确、首末位置、与道路对齐、可建区合理、基地状态板在末点、敌人不穿模）。
5. **资产文件夹约定**：如 `ReplicatedStorage/Assets/{Towers,Pets,Enemies}`、`Workspace/{PathNodes,Towers}`，供 §8 的 `modelId` 解析。

## 10. Out of Scope（本阶段明确不做）

- 不实现：新 UI / 新地图 / 新塔模型 / 新宠物模型 / 新敌人模型 / 新玩法特性 / DataStore 迁移 / 新 remote。
- 不改任何 §1 受保护核心文件的逻辑或契约。
- 本阶段仅交付本规划文档与 `MVP-Core-Loop.md` 的一处指引链接。

## 11. Acceptance Criteria（本规划阶段验收）

1. 文档覆盖：受保护核心、视觉替换四原则、地图规则、塔/宠物/敌人视觉-逻辑分离、技能树 UI 规则、未来字段提案、17B 计划、out-of-scope。
2. **未改** gameplay 代码、**未** bump DataVersion、**未改** MainUI、**未碰**受保护文件、**未加** remote。
3. 工程可正常构建（`default.project.json` 合法）。
