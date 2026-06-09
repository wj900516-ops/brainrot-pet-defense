# Phase 11.5 — Tower Placement Ghost Preview UX

> 目标：在不改塔战斗的前提下，提升放置体验 —— 鬼影预览 + 鼠标选址 + 左键确认。
> server-authoritative；客户端鬼影仅 UX，最终由服务端完整校验。

## 交互流程

```
按 T → 进入放置模式
  → 鼠标处显示半透明鬼影塔（随鼠标移动）
  → 客户端近似校验着色：绿色=可放 / 红色=不可放（近路径/近塔/太远）
左键 → 确认：把"鼠标地面落点"发给服务端
  → TowerRemote:FireServer("PlaceTower", groundPoint)
  → 服务端 TowerService.TryPlaceTower(player, groundPoint) 完整校验 → 扣币 + 放置
  → 成功 pushData 刷新金币；回推 "Result" → 客户端 toast
Esc / 右键 → 取消放置模式
```

## 客户端（TowerPlacer.client.lua）

- 按 T 进入/退出放置模式；进入时创建/显示鬼影（`ForceField` 半透明 Part，`CanQuery=false`）。
- `RenderStepped` 每帧用相机射线（`ViewportPointToRay` + `Workspace:Raycast`，排除鬼影/自身角色/Towers）求地面落点，更新鬼影位置与颜色。
- 客户端近似校验（**仅 UX**）：距玩家 ≤ `MAX_PLACE_DISTANCE`、距路线**逐段**（点到线段 XZ 距离，节点自然排序后连段）≥ 8、距 `Towers` ≥ 8。因此 ghost 在两航点之间的路面上也会变红。
- 左键确认发送落点；Esc/右键取消。**客户端只发位置**，不发花费/拥有者/属性/奖励。
- 反馈 toast 与提示均在**独立 ScreenGui**，**不改 MainUI**。

## 服务端（TowerService.TryPlaceTower(player, requestedPosition)）

复用 Phase 11 校验，并新增反作弊（顺序即校验顺序）：

1. 有数据 / 有角色 + HRP。
2. **有限性校验（先于一切距离/路径/金币/放置判定）**：若提供了 `requestedPosition`，
   它必须是**有限的 Vector3** —— 拒绝**非 Vector3、NaN（`n ~= n`）、±Inf**。否则 `bad_position`。
   （为空则回退玩家脚下，向后兼容。）
3. **反作弊**：落点距玩家水平距离 ≤ `MAX_PLACE_DISTANCE (60)`（否则 `too_far`）。
4. **反作弊（拒绝，不夹紧）**：落点 Y 必须在 `[玩家Y - VERTICAL_BAND, 玩家Y + VERTICAL_BAND]`
   （`VERTICAL_BAND = 30`）内；**超出直接拒绝**：高于上界 → `too_high`，低于下界 → `too_low`。
   不再 clamp 后强行放置。
5. 金币 ≥ cost（否则 `not_enough_coins`，不扣币）。
6. **距路径 ≥ 8 —— 对【整条路线折线】判定，而非仅航点**：用 `EnemyService.GetRoute()` 取有序航点，
   逐段（`Node_i -> Node_{i+1}`）用 `distancePointToSegmentXZ`（XZ 平面点到线段最近距离）检查；
   任一段 < 8 → `too_close_to_path`。
   → **关键**：判定基于"最终请求塔位"（`requestedPosition` 或回退玩家脚下），与玩家站位无关；
   因此**站在草地、用鼠标把塔放到两航点之间的路面上，也会被拒绝**。
7. 距其它塔 ≥ 8（否则 `too_close_to_tower`）。
8. 全过 → **先扣币** → 建塔（恰好一座）。任一失败 → 安全拒绝、**不扣币**、不建塔。

**服务端始终不信任客户端位置**：客户端发来的落点只是意图，所有判定在服务端重做；
**畸形/非有限位置一律拒绝**，**越界竖直位置一律拒绝（不夹紧）**。

失败 `reason` 取值：`bad_position` / `too_far` / `too_high` / `too_low` /
`not_enough_coins` / `too_close_to_path` / `too_close_to_tower` / `no_character` / `no_data`。

## 网络

- **未新增 remote**：沿用既有 `TowerRemote`。
  - C→S `"PlaceTower", groundPoint`（仅位置意图）
  - S→C `"Result", { success, reason, cost? }`（新增 reason：`too_far`）

## 边界 / 兼容

- **未改动** `MainUI.client.lua`（放置 UX 全在 TowerPlacer 客户端脚本）。
- **未改动**受保护文件：`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `TaskConfig.lua`。
- 塔模型/占位视觉、扣币行为、`Workspace.Towers` 组织方式均不变。
- **未改动** DataStore 名称 / `CURRENT_DATA_VERSION`；塔不持久化。

## 范围外

塔攻击 / 升级 / 出售 / 商店 / 抽卡 / 新塔 / 付费 / 大型 MainUI 重设计 / 持久化塔。

## 已知限制

- 客户端校验为近似，可能与服务端略有出入（如地面高度/排序边角情形）；以服务端结果为准。客户端与服务端均已用"点到线段"距离判定路径。
- 地面落点依赖鼠标射线；指向天空/无命中时鬼影隐藏，确认无效。
- 服务端竖直方向为"越界即拒绝"（非地面射线）；不同地形可能略有高低偏差，但落点 Y 必须在玩家附近带宽内。
- 右键取消同时可能触发相机右键行为（MVP 可接受）。
