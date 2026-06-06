# Phase 4 — Player Data Persistence（玩家数据持久化）

> 目标：让玩家进度在离开/重进后仍然保留。
> 方案：原生 `DataStoreService` + 安全封装。**本阶段不引入 ProfileService。**
> 不含：宠物 / 商店 / 商业化 / 复杂战斗 / UI 重设计。

## 持久化的内容

`Coins` / `Level` / `XP` / `CompletedTasks` / `Inventory` / `Settings`，
以及任务状态（仅标识/状态，**不含** TaskConfig 的完整定义）：`currentTaskId` / `currentTaskProgress` / `taskChainIndex`。

## 数据 Schema（版本化）

```lua
{
  DataVersion = 1,
  Coins = 0,
  Level = 1,
  XP = 0,
  CompletedTasks = {},        -- [taskId] = count
  Inventory = {},
  Settings = {},
  Task = {
    currentTaskId = "defeat_training_dummy_1",
    currentTaskProgress = 0,
    taskChainIndex = 1,
  },
}
```

全部为基础类型 / 基础类型的表 → 可序列化。无 Instance 引用，不保存任务定义。

## 分层与所有权

- **PlayerDataService** 拥有持久化状态：`LoadData` / `SaveData` / `GetData` / `GetPublicData` /
  `AddCoins` / `AddXP` / `GetTaskState` / `SetTaskState` / `ClearData`。
- **TaskService** 只通过 `GetTaskState` / `SetTaskState` 干净地读写任务状态；
  每次任务状态变化都写回（`syncToData`），保证保存的 blob 始终最新。
- **TaskConfig** 仍是任务定义的唯一来源；存档只存 id/进度/下标。

## Load / Save 流程

```
PlayerAdded → PlayerDataService.LoadData(player)      [pcall GetAsync ×重试]
  ├─ 成功+数据 → reconcile(loaded) 合并进全新默认值
  ├─ 成功+nil  → 新玩家 → defaultData()
  └─ 失败/无 store → defaultData() + saveBlocked=true（本会话不保存，避免覆盖云端）
→ 玩家在加载期间离开？(player.Parent==nil) → 直接返回，不恢复/不推送
→ TaskService.RestoreOrAssign(player)                [读 data.Task → 设置内存态 → 写回 canonical]
→ 推送 data + task 给客户端

游戏中 → Reward/PlayerData 改 Coins/XP/Level；TaskService 每次变化写回 data.Task

PlayerRemoving → PlayerDataService.SaveData(player)   [saveBlocked 则跳过；pcall SetAsync ×重试]
→ ClearData / ClearTask

game:BindToClose → 为所有在场玩家 SaveData

周期自动保存（安全网） → 每 180s 遍历在场玩家并 SaveData（尊重 saveBlocked）
```

## 保存触发点（三处）

| 触发 | 时机 | 作用 |
|------|------|------|
| `PlayerRemoving` | 玩家离开 | 主要保存点：保存该玩家最新进度后清理内存 |
| `game:BindToClose` | 服务器关闭 | 关停时保存所有在场玩家 |
| 周期自动保存 `StartAutoSave()` | 每 `AUTO_SAVE_INTERVAL_SECONDS = 180s` | **安全网**：缩小服务器崩溃/异常关闭导致的进度丢失窗口 |

> **自动保存是安全网，不是替代品。** 正常退出仍依赖 `PlayerRemoving`，正常关停仍依赖 `BindToClose`；
> 自动保存只是额外兜底，降低异常情况下的最大数据丢失量（最多丢失约一个自动保存间隔的进度）。
>
> 实现要点：后台 `task.spawn` 循环，先 `task.wait(间隔)` 再遍历，绝不紧密空转；
> 每个玩家的 `SaveData` 已内部 `pcall` 且尊重 `saveBlocked`（加载失败的会话被跳过，不会用默认值覆盖云端），
> 外层再 `pcall` 双保险——**单个玩家保存失败不会中断整个循环**；玩家之间轻微错峰，避免同帧批量 `SetAsync`。

## TaskService 恢复行为（`RestoreOrAssign`）

1. 无 `currentTaskId`（新玩家）→ 分配起始任务。
2. `currentTaskId` 仍在 TaskConfig 中 → 按 id 恢复；进度 clamp 到 `0 .. goal-1`（重进不会自动完成）。
3. `currentTaskId` 过时 → 回退到 `taskChainIndex`（若合法），进度重置 0，并告警。
4. id 与下标都无效 → 分配起始任务，并告警。
5. 解析完成后把 canonical 状态写回 `PlayerDataService.SetTaskState`。

## 失败 / 安全行为

- `GetDataStore` / `GetAsync` / `SetAsync` 全部 `pcall` 包裹；**有限重试**（3 次，每次间隔 2s），非无限。
- **加载失败** → 玩家用默认数据照常游玩；会话标记 `saveBlocked`，离开时**跳过保存**以免覆盖云端好数据。
- **保存失败** → 清晰 `warn`，**不崩服**。
- **Studio API 未开启** → `GetDataStore`/`GetAsync` 失败被捕获 → 无持久化模式，告警并继续。
- 无共享表引用：`reconcile` 基于全新默认值并深拷贝 `Inventory` / `Settings`。
- 不无限 yield：对 DataStore 从不 `WaitForChild`，仅有限重试。
- 玩家加载期间离开：`player.Parent` 守卫，跳过恢复与推送。

## Studio 测试前置：API Services

DataStore 仅在"已发布且开启 API 访问"的场景，或 Studio 勾选
**Game Settings → Security → Enable Studio Access to API Services** 时可用。
未开启时本实现进入无持久化模式（可玩、有告警、不崩）。

### Mode A — API Services 关闭
1. Play Solo。
2. 游戏正常运行（假人/任务/UI 正常）。
3. Output 出现"无持久化/读取失败"告警。
4. 无崩溃、无红色 game-code 报错。

### Mode B — API Services 开启
1. 勾选 Enable Studio Access to API Services。
2. Play Solo，赚取金币/经验并推进任务。
3. Stop。
4. 再次 Play Solo。
5. 确认 Coins/XP/任务状态已恢复。
6. 无红色 Output 报错。

## 为什么暂缓 ProfileService

- 本阶段优先"简单、可审查、零第三方依赖"，原生 DataStore 足以建立持久化基座。
- ProfileService 的核心价值是**会话锁（session-locking）**，防止同一玩家在多服/快速重连时的数据竞争与覆盖；
  这属于上线前的健壮性增强，超出本基座阶段范围。

### 若将来采用 ProfileService，需要迁移的点

- 把 `LoadData`/`SaveData` 替换为 Profile 的 `LoadProfileAsync` + `:Reconcile()` + `:Release()`，
  并保留现有 `PlayerDataService` 对外 API（`GetData/GetPublicData/GetTaskState/SetTaskState/...`）不变，
  这样 `TaskService` / `ServerInit` 无需改动。
- 用 Profile 的模板替代 `defaultData()`；用 `:Reconcile()` 替代手写 `reconcile()`。
- 用 Profile 的会话锁替代当前的 `saveBlocked` 简易保护。
- `BindToClose` 改为释放所有 Profile。
- 现有 v1 schema 可直接作为 Profile 模板，`DataVersion` 字段继续用于迁移。
