# Phase 11 — Tower Placement MVP（塔放置）

> 目标：玩家可以花金币在合法地面放置一座基础塔。
> **仅放置**；塔战斗留待 Phase 12。server-authoritative、占位视觉、不持久化。

## 流程

```
玩家按 T
  → 客户端 TowerPlacer 只发意图：TowerRemote:FireServer("PlaceTower")（不带位置/花费）
  → ServerInit 监听 → TowerService.TryPlaceTower(player)
      读取玩家角色 HRP 位置 → 校验（金币 / 有角色 / 距路径 / 距其它塔）
        通过 → 扣金币 + 生成占位塔（世界 Anchored Part）→ { success=true, reason="placed", cost }
        失败 → { success=false, reason=... }（不扣币）
  → 成功则 pushData(player) 刷新 MainUI 金币
  → TowerRemote:FireClient(player, "Result", result) 回推结果
  → 客户端按 reason 显示短暂 toast（独立 ScreenGui，非 MainUI）
```

## 放置模式（输入）

> **Phase 11.5 起改为鬼影预览模式**（按 T 进入 → 鼠标处显示预览 → 左键确认）。
> 详见 [`Phase11_5-TowerPlacementUX.md`](Phase11_5-TowerPlacementUX.md)。
> 服务端仍完整校验客户端发来的位置（不信任客户端），并新增"距玩家不太远"等反作弊校验。

- Phase 11（已被 11.5 取代）：按 T 在**玩家脚下**直接放置，客户端不发位置。
- Phase 11.5：按 T 进入放置模式，客户端发送**鼠标地面落点**作为意图，服务端最终校验+扣币+放置。

## 服务端校验（server-authoritative）

`TowerService.TryPlaceTower(player)` 依次校验：
1. 有玩家数据。
2. 有角色 + HumanoidRootPart（否则 `no_character`）。
3. **金币 ≥ cost**（否则 `not_enough_coins`，不扣币）。
4. **距任一路径航点 ≥ `MIN_DISTANCE_FROM_PATH (8)`**（水平距离；否则 `too_close_to_path`）。
5. **距任一已放置塔 ≥ `MIN_DISTANCE_BETWEEN_TOWERS (8)`**（否则 `too_close_to_tower`）。

全部通过 → **先扣金币**（`PlayerDataService.AddCoins(player, -cost)`）→ 生成塔。
任一失败 → 安全拒绝、**不扣币**、不建塔。

**安全性**：客户端只发意图；**不能**设置位置 / 花费 / 拥有者 / 伤害 / 奖励；**不能免费造塔**（金币校验 + 扣费在服务端）。

## 塔占位视觉

- 蓝色 Anchored `Part`（`size 4×8×4`），头顶 BillboardGui 标签 "Tower"。
- 放在 `Workspace.Towers` 文件夹下；自动复制到客户端（无需 remote 同步视觉）。
- `CanCollide = true`（实体障碍）；敌人以 CFrame 移动、忽略碰撞，故塔**不会卡住敌人**；
  再加上"距路径 ≥8"校验，敌人路线不会被异常阻挡。

## 花费 / 配置

- `TowerConfig`（`ReplicatedStorage/Config/TowerConfig`）：`basic_tower` 固定 `cost = 100`。
- `range/damage/fireInterval` 为 **Phase 12 战斗 stub**，本阶段不读取。
- TowerConfig 缺失时 `TowerService` 使用内置兜底塔（不崩）。

## 网络

- 新增 **`TowerRemote`**（RemoteEvent，经 `Net.TowerRemote()`，与既有 remote 同模式）。
  - C→S `"PlaceTower"`（仅意图，无负载）
  - S→C `"Result", { success, reason, cost? }`
- 无任何让客户端设定塔属性/奖励/免费造塔的通道。

## 持久化

- **塔不持久化**：仅存在于当前会话；服务器关闭/玩家离开即移除（`PlayerRemoving` 清理该玩家的塔）。
- 金币消费走既有玩家数据（金币本就持久化），**未改动** DataStore 名称 / `CURRENT_DATA_VERSION`。

## 边界

- **未改动** `MainUI.client.lua`（金币变化经既有 `pushData` 显示；放置反馈用独立 ScreenGui toast）。
- **未改动**受保护文件：`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `TaskConfig.lua`。
- `CombatService` 未改动；`EnemyService` 仅新增只读 `GetRoute()`。
- 既有波次/路径/基地/宠物战斗行为不变。

## 范围外（Out of Scope）

塔攻击逻辑 / 升级 / 出售 / 选塔 UI / 商店 / 抽卡 / 新敌人 / Boss / 付费 / 持久化塔 / 大型 UI 重设计。

## 已知限制

- 放置点 = 玩家脚下，无幽灵预览/拖拽放置（MVP）。
- 地面高度用 `HRP.Y - GROUND_DROP(3)` 近似；不同地形可能略有高低偏差。
- **金币消费会持久化，但塔不持久化**：放塔后重进会保留扣费、但塔消失（符合"塔不持久化"范围；后续阶段可加塔持久化）。
- 塔尚不攻击（Phase 12）。

> 路径见 [`Phase10-RoutePathing.md`](Phase10-RoutePathing.md)；总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
