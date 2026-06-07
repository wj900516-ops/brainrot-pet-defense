# Phase 6 — Pet Ownership / Equip Persistence（宠物拥有与装备持久化）

> 目标：把 Phase 5 的"隐式起始宠物"升级为**存档拥有 + 装备**的真实数据模型。
> 范围：单宠物；不含宠物 UI / 抽卡 / 商店 / 商业化 / 多槽行为 / 升级 / 稀有度 / Option B 战斗 / 新 remote。

## 行为

新玩家加入 → 自动授予 `starter_toast` 并装备 → PetService 据存档生成已装备宠物 → 离开保存 →
重进仍拥有并装备 `starter_toast` → Toasty 再次生成。**不会每次加入重复授予。**

## DataVersion 2 —— 数据 Schema

```lua
{
  DataVersion = 2,
  Coins = 0, Level = 1, XP = 0,
  CompletedTasks = {},
  Inventory = {
    Pets = {
      { uid = "starter_toast_1", petId = "starter_toast", acquiredAt = <os.time()> },
    },
  },
  EquippedPets = { "starter_toast_1" },   -- 数组（当前仅 1 个，前向兼容多槽）
  Settings = {},
  Task = { currentTaskId = "...", currentTaskProgress = 0, taskChainIndex = 1 },
}
```

- **按 uid 存拥有关系**，**按 petId 存类型**，**按 uid 存装备**（不是 petId）。
- 全部可序列化；**不存** PetConfig 的完整定义（视觉/数值由 PetConfig 解析）。
- uid 采用可读方案 `petId_n`（如 `starter_toast_1`）；本阶段不用 GUID。

## 为什么 DataStore 名称保持 `PlayerData_v1`

DataStore 名称与记录内的 `DataVersion` 是两回事。**更换 DataStore 名称会孤立 Phase 4/5 的旧存档**，
因此名称保持 `PlayerData_v1` 不变；schema 升级通过记录内 `DataVersion 1 → 2` 的迁移完成。

## v1 → v2 迁移行为

迁移在 `reconcile()`（结构）+ `EnsureStarterPet()`（策略）两步完成：

- **保留**：`Coins` / `Level` / `XP` / `CompletedTasks` / `Task` / `Settings`，**绝不清空**。
- **补齐**：若缺 `Inventory.Pets` → 设为空数组；若缺 `EquippedPets` → 空数组。
- **校验**：`sanitizePets` 丢弃缺 `uid`/`petId` 的非法条目；`sanitizeEquipped` 仅保留指向"已拥有 uid"的装备项（无主的丢弃并告警）。
- **授予策略**（`EnsureStarterPet`，加载后调用一次）：
  - 拥有 0 只 → 授予并装备起始宠物（覆盖：新玩家 + 旧 v1 玩家首次进入）。
  - 有宠物但无有效装备 → 装备已拥有的第一只（兜底，告警）。
  - **已有宠物则不再授予** → 避免每次加入重复 Toasty。
- 末尾 `DataVersion = 2` 写回；下次保存即为 v2。

## PlayerDataService 宠物 API（拥有持久化宠物状态）

| API | 作用 |
|-----|------|
| `GetPets(player)` | 返回拥有宠物列表**拷贝** |
| `GetEquippedPets(player)` | 返回已装备 uid 列表**拷贝** |
| `GetEquippedPetEntries(player)` | 把装备 uid 解析为宠物条目**拷贝**（跳过无主 uid，告警）；供 PetService |
| `GrantPet(player, petId)` | 生成可读唯一 uid（`petId_n`），追加并返回 uid |
| `EquipPet(player, uid)` | 单槽装备（仅当拥有该 uid）；成功返回 true |
| `EnsureStarterPet(player, starterPetId)` | 0 只则授予+装备；有宠物但无有效装备则装备第一只 |

所有读取返回拷贝；玩家之间不共享表引用；非法/无主数据清晰告警。
`PlayerDataService` **不**依赖 `PetConfig`：起始 petId 由 `ServerInit` 通过 `PetService.GetStarterPetId()` 传入。

## PetService 生成行为（数据驱动）

```
SpawnPet(player)
  → PlayerDataService.GetEquippedPetEntries(player) 取第一只
      ├─ 无装备条目（EnsureStarterPet 后不应发生）→ 告警并跳过生成（不再隐式给 Toasty）
      └─ 有条目 → PetConfig.GetPet(entry.petId) 解析视觉
            ├─ petId 过时/缺失（配置不存在）→ 清晰告警（含 uid + petId）并【跳过生成】
            │     不回退起始视觉、不修改玩家数据、不授予新宠物、不崩服
            └─ 正常 → 用该定义构建占位宠物
  → 攻击仍走 Option A：PetService → DummyTargetService.HandleHit(owner)（未改动）
```

> **过时 petId 策略（PR #5 评审收紧）**：回退起始视觉会掩盖配置错误、误导玩家。
> 因此过时/缺失的 petId 一律**告警 + 跳过生成**，让问题可见，留待后续迁移/清理阶段统一处理。

PetService 现在依赖 `PlayerDataService`（读装备）与 `PetConfig`（解析视觉），但**不**依赖
`TaskService` / `RewardService` / `GameEventService`，也**不**发放金币/经验/任务进度/奖励/写 DataStore。

## 生命周期（ServerInit）

```
PlayerAdded → LoadData → (leave guard)
  → PlayerDataService.EnsureStarterPet(player, PetService.GetStarterPetId())   ← 在 SpawnPet 之前
  → TaskService.RestoreOrAssign → push → PetService.SpawnPet(player)
PlayerRemoving → DespawnPet → SaveData（含 Inventory.Pets / EquippedPets）→ ClearData
```

既有 load/save/auto-save/task-restore 流程保持不变；保存天然包含新字段。

## 边界（未改动）

`DummyTargetService` / `GameEventService` / `TaskService` / `RewardService` / `MainUI` / `Net.lua` / `TaskConfig.lua` 均未改动。

## 为什么暂缓宠物 UI 与库存管理

- 本阶段聚焦"持久化数据模型"这一基座；先把"拥有/装备"存对、迁移稳，再谈交互。
- 宠物 UI（查看/切换/装备）、多槽、获取系统（抽卡/商店）等属于后续阶段，
  会基于本阶段的 `Inventory.Pets` / `EquippedPets` 之上构建。

## 未来升级路径

- **多槽装备**：`EquippedPets` 已是数组，扩展到多槽时 PetService 生成多只即可。
- **宠物 UI**：通过现有 `GetPets` / `GetEquippedPets` 读取，新增 remote + 客户端界面。
- **获取系统**：用 `GrantPet` 接入抽卡/商店；用 `EquipPet` 切换。
- **Option B 战斗**：宠物按自身位置攻击（需给 DummyTargetService 增加附加入口），与本阶段数据模型正交。

> 宠物攻击循环见 [`Phase5-StarterPet.md`](Phase5-StarterPet.md)；持久化基座见 [`Phase4-Persistence.md`](Phase4-Persistence.md)；核心循环总览见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
