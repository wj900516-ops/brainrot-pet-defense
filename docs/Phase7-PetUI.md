# Phase 7 — Pet UI + Secure Equip/Unequip（宠物界面与安全装备流程）

> 目标：给玩家一个最小界面查看拥有的宠物，并安全地 Equip/Unequip Toasty。
> 范围：单装备槽；server-authoritative；不含抽卡 / 商店 / 商业化 / 稀有度 / 升级 / 多槽 / Option B 战斗 / 波次。

## 行为

加入 → 拥有 `starter_toast_1`（若当前装备则 Toasty 出现）→ 打开 Pet UI → 列出宠物及装备状态 →
点击 Equip/Unequip → 客户端只发意图 → 服务端校验并改 `EquippedPets` → PetService 刷新宠物 → 回推最新列表。
**装备状态通过既有 DataStore 保存路径持久化**（含"零装备"状态）。

## Remote 协议 —— 新增 `PetRemote`（RemoteEvent，action 字符串）

```
C→S "RequestPets"          → S→C "Pets", publicPets
C→S "EquipPet",   uid      → 校验 → 装备 → 刷新宠物 → S→C "Pets", publicPets
C→S "UnequipPet", uid      → 校验 → 卸下 → 刷新宠物 → S→C "Pets", publicPets
S→C "Pets", publicPets     → 加入时也会主动推送一次
```

客户端**只发意图**：`PetRemote:FireServer("EquipPet", uid)` / `PetRemote:FireServer("UnequipPet", uid)`。
RemoteEvent 由 `Net.PetRemote()` 在服务端创建、客户端等待（与既有 PlayerDataRemote/TaskRemote 同模式）。

## 公开宠物数据形状（over the wire）

```lua
publicPets = {
  { uid = "starter_toast_1", petId = "starter_toast", displayName = "Toasty", equipped = true },
}
```

- `PlayerDataService.GetPublicPets` 返回安全字段 `{ uid, petId, equipped }`（不暴露完整存档表）。
- `displayName` 由 `ServerInit` 通过 `PetService.GetDisplayName(petId)` 注入，
  使 `PlayerDataService` 不依赖 `PetConfig`（保持分层）。

## 服务端校验（service-authoritative）

**Equip**：
1. `uid` 为字符串。
2. `PlayerDataService.IsPetOwned(player, uid)` —— 玩家确实拥有该 uid。
3. 该 uid 的 `petId` 存在于 PetConfig（`PetService.HasPet(petId)`）—— 拒绝装备无法生成的过时宠物。
4. `PlayerDataService.EquipPet(player, uid)`（再次校验拥有，设 `EquippedPets = { uid }`）。
5. `PetService.RefreshPet(player)` → 回推 `"Pets"`。
任一校验失败 → 告警并安全忽略，不改状态。

**Unequip**：
1. `uid` 为字符串。
2. `PlayerDataService.UnequipPet(player, uid)` —— 仅当该 uid 当前已装备才生效，移除后单槽变为零装备。
3. `PetService.RefreshPet(player)`（无装备 → SpawnPet 跳过，等价卸下）→ 回推 `"Pets"`。
未装备该 uid → no-op。

**安全性**：客户端只发意图；不能授予宠物、不能直接改 `Inventory`/`EquippedPets`；
未知 action / 非法 uid / 非拥有 uid / 过时 petId 全部被安全拒绝；Pet UI 不触发任何金币/经验/任务/奖励变更。

**服务端去抖（防刷）**：`ServerInit` 对**变更类**动作做每玩家冷却
`PET_MUTATION_COOLDOWN_SECONDS = 0.5s`：
- 仅作用于 `EquipPet` / `UnequipPet`；**不影响** `RequestPets`（只读）。
- 服务端独有；冷却中**直接返回、不改状态、不刷屏 Output**（静默忽略刷请求）。
- `PlayerRemoving` 时清理该玩家的去抖记录。
- 纯服务端，不引入任何客户端信任。

## PlayerDataService API 变化

| API | 作用 |
|-----|------|
| `GetPublicPets(player)` | 返回 `{ uid, petId, equipped }` 安全列表（拷贝） |
| `IsPetOwned(player, uid)` | 是否拥有该 uid |
| `UnequipPet(player, uid)` | 仅当已装备才移除（单槽 → 零装备），返回是否变化 |
| `EquipPet(player, uid)` | （既有）单槽装备，拥有校验 |
| `EnsureStarterPet(player, starterPetId)` | **Phase 7 调整**：仅在拥有 0 只时授予+装备；**不再**"有宠物但无装备时自动装备第一只" |

> **EnsureStarterPet 调整原因**：支持玩家"主动卸下并持久保持零装备"。否则下次加入会被自动重新装备，
> 与 Unequip 的持久语义冲突。该调整为运行时逻辑，**无 schema 变化、无 DataVersion 变更**，
> 对既有 Phase 6 存档无副作用（它们始终处于已装备状态）。

## PetService 刷新行为

`PetService.RefreshPet(player) = DespawnPet(player) + SpawnPet(player)`：
- 装备变化（Equip）→ 销毁旧的、按最新装备数据生成新的；
- 零装备（Unequip）→ SpawnPet 因无装备而跳过，等价卸下。
攻击仍走 Option A：`PetService → DummyTargetService.HandleHit(owner)`（未改动）。PetService 不发奖励、不写 DataStore。

## UI 行为（PetUI.client.lua，独立 ScreenGui）

- **中右** "Pets (P)" 开关按钮（避开顶栏 inset 与底部 Studio UI）；面板在**屏幕正中**清晰显示。
- 面板列出每只宠物：显示名 + 装备状态（Equipped / Not equipped）+ Equip/Unequip 按钮。
- 打开面板时 `RequestPets`；收到 `"Pets"` 即重建列表。
- 仅发意图，不做本地状态变更（以服务端回推为准）。
- **MainUI.client.lua 未改动**，既有 Coins/XP/Task UI 保持不变。

### 点击可靠性处理（Studio 鼠标点击问题）

实现（与代码一致）：

- ScreenGui `DisplayOrder = 1000`、`IgnoreGuiInset = true`、`ResetOnSpawn = false`、`ZIndexBehavior = Sibling`；
  各元素高 `ZIndex`（按钮 200 / 面板 100 / 内容 101–103）。
- **非按钮 GuiObject（面板/标签/列表/行）一律 `Active = false`**，避免透明 Frame/Label 拦截点击；
  仅 TextButton 设 `Active/Selectable = true`。
- 每个按钮同时连接 `Activated` 与 `MouseButton1Click`；并额外提供一条
  **`UserInputService.InputBegan` 矩形命中后备**（按鼠标/触摸坐标命中按钮）。三条路径共享同一去抖，
  保证一次点击只触发一次。
- **未使用 `Modal`**：`Modal = true` 会全局释放/改变鼠标光标，可能干扰其它 GUI 与相机/输入，
  因此移除；改用上面的"矩形命中后备 + 非按钮 Active=false"来提升可点击性。
- **未新增任何全屏遮挡 Frame**。

> **关于鼠标点击的现实说明**：**人工手动鼠标点击在 Roblox Studio 中验证通过**；
> 但 Codex / Computer Use 的**自动化鼠标点击在 Studio 中可能不稳定**（环境因素，非游戏代码问题）。
> 因此并不保证自动化鼠标一定可点击；键盘 P/E/U 后备走的是**完全相同的服务端权威路径**，可作为可靠验证手段。

### 键盘快捷键（临时 MVP / 可访问性后备）

| 键 | 作用 | 条件 |
|----|------|------|
| `P` | 打开/关闭宠物面板 | 任何时候 |
| `E` | 装备列表中**第一只**宠物 | 面板打开时 |
| `U` | 卸下列表中**第一只已装备**宠物 | 面板打开时 |

> 这些快捷键仍**只发意图**（`PetRemote:FireServer("EquipPet"/"UnequipPet", uid)`），
> 服务端仍是唯一真相、负责全部校验；快捷键不修改任何本地持久状态。属临时测试/可访问性手段。

## 持久化

Equip/Unequip 改的是内存中的 `EquippedPets`，由既有 `SaveData` / 自动保存 / `BindToClose` 持久化。
**无 DataVersion 变更**（`EquippedPets` 字段在 Phase 6 已存在，可为空数组）。
重进恢复装备状态（含"零装备"）。

## 为什么仍是单槽 / 后续延期项

- 本阶段聚焦"安全的装备/卸下 + 最小 UI"，`EquippedPets` 用数组保持前向兼容，但行为限制为单槽。
- **多槽装备**：扩展 `EquipPet`/UI 即可，数据结构已就绪。
- **抽卡 / 商店 / 获取**：用 `GrantPet` 接入（服务端授予），客户端永不授予。
- **宠物升级 / 稀有度**：未来在 PetConfig + 数据模型扩展。
- **Option B 战斗**：宠物按自身位置攻击，与本阶段正交。

> 数据模型见 [`Phase6-PetInventory.md`](Phase6-PetInventory.md)；宠物攻击见 [`Phase5-StarterPet.md`](Phase5-StarterPet.md)；核心循环见 [`MVP-Core-Loop.md`](MVP-Core-Loop.md)。
