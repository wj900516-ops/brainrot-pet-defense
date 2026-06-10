# Phase 16C — 技能树 UI（玩家面板 MVP）

> 把 Phase 16B 的开发用 `SkillTreeDebug` 升级为**面向玩家**的技能树面板：按 K 开关，4 个分支 Tab + 技能卡片列表。
> 复用既有 `SkillRemote`，**服务端仍是权威**；只新增客户端 UI + 服务端一处只读字段。不加技能效果、不改持久化。

## 1. Overview（概述）

- 新增 [`SkillTreeUI.client.lua`](../src/StarterGui/SkillTreeUI/SkillTreeUI.client.lua)：独立 ScreenGui（**不改 MainUI**）。
- 静态树结构（名称/分支/花费/上限/说明）由客户端从 `ReplicatedStorage.Config.SkillTreeConfig` 读取（仅显示用）。
- 等级/点数/可消费 allowlist 来自服务端 `SkillRemote "State"`。
- 旧 `SkillTreeDebug` 面板**默认关闭**（flag 门控，仅 QA 可手动开启），避免与玩家面板同时出现。

## 2. UI（最小、清爽）

- 居中面板，顶栏：`Skill Tree` 标题 + `SP: N` + 关闭按钮。
- 顶部 4 个分支 Tab：`Economy / Tower / Pet / Defense`（顺序取自配置 `Branches.order`）。
- 下方滚动卡片列表：当前分支的每个技能一张卡片，显示
  **名称（分支）/ 说明 / `Rank r/max  Cost c`** 与右侧动作：
  - 可消费技能（allowlist 内）：`+ cost` 按钮；满级显示 `MAX`、点数不足显示灰色 `+ cost`（禁用）。
  - 未启用技能：`Coming Soon` 标签（不可点）。
- 底部 toast 显示消费结果/失败原因。无连线图 / 无节点动画 / 无图标要求（MVP）。

## 3. 开关

- **按 K** 切换面板显示；关闭按钮亦可关。打开时主动 `RequestState` 拉取最新状态。
- 启动时请求一次（即使未开），保证打开即有数据。

## 4. 消费（复用 SkillRemote，服务端权威）

- 客户端只发 `skillRemote:FireServer("SpendPoint", skillId)`（**仅意图**，从不发 rank/cost/点数/伤害/奖励）。
- 服务端 `SkillTreeService.TrySpend` 做全部校验（去抖 0.2s + 锁 + 点数/上限/前置/allowlist）；成功后回推 `Result` 并主动再推 `State`，UI 自动刷新。
- 失败 `Result.reason` → 清晰中/英提示：
  `not_enough_points`→Not enough Skill Points、`max_rank`→Already at max rank、`not_implemented`→Coming soon、
  `too_fast`→Slow down、`busy`→Busy、`prereq_*`→Requirements not met。

## 5. 服务端改动（仅一处，只读）

`SkillTreeService.GetPublicState` 在原有 `{ skillPoints, totalPoints, unlocked, skills }` 上**新增** `enabledIds`
（= Phase 16B allowlist：`eco_kill_coins` / `twr_damage` / `pet_damage`），供 UI 区分"可消费 vs Coming Soon"。
**不改任何消费校验逻辑**。`skills` 字段保留以兼容（调试面板默认关闭）。

## 6. Debug 面板处理

`SkillTreeDebug.client.lua` 顶部加 `DEBUG_PANEL_ENABLED = false` + 提前 `return`：默认不构建任何 UI、不接线、不抢输入。
QA 需要时改 `true` 即可恢复。**正式玩家看不到调试面板**，避免双面板并存。

## 7. Safety / 边界

- **不改**服务端消费规则、**不加**技能效果、**不实现** Defense/Keystone/宠物树/respec。
- **不改** `DATASTORE_NAME`、**不 bump** `CURRENT_DATA_VERSION`（无持久化变化）。
- **不加新 remote**（复用 `SkillRemote`）。**不改** MainUI、**不碰**受保护文件
  （DummyTargetService / GameEventService / TaskService / TaskConfig.lua）。

## 8. Acceptance Criteria（验收）

1. 按 K 开关面板；`SP` 正确显示。
2. Economy 显示 `Kill Coin Bonus`、Tower 显示 `Tower Damage`、Pet 显示 `Pet Damage`，均可消费。
3. Defense 分支存在；其技能（及其它未启用节点）显示 `Coming Soon`、不可消费。
4. 消费成功更新 rank 与 SP；失败显示清晰原因。
5. 升级（XP/任务）后面板状态随服务端 `State` 刷新（Phase 16B 同步修复已覆盖）。
6. 重进保留等级；R 重开不重置技能；塔/宠物/波次系统不受影响。
7. 调试面板默认不可见。

## 9. Known Limitations（已知限制）

- 仅 3 个技能可消费；其余节点显示 `Coming Soon`。
- 无连线图/动画/图标；纯 Tab+列表布局。
- Defense / Keystone / 宠物技能树 / respec 未实现。
- 卡片说明过长会截断（`TextTruncate`）。
