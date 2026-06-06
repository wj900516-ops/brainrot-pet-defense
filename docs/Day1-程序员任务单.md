# Day 1 工作单 - Brainrot Pet Defense
> 直接微信发给程序员的版本

---

## 今天目标：搭骨架，不写逻辑

今天不做功能，只做结构。明天才开始写代码。

---

## 10 条待办（按顺序做）

### 1. 新建 Roblox Studio 工程
名字：BrainrotPetDefense

### 2. 搭 Workspace 目录
在 Workspace 下建这些 Folder：
- `Map` （放地面、装饰）
- `PathNodes` （放路径点）
- `TowerSpots` （放塔位）
- 放一个 Part 命名 `SpawnPoint`（怪出生点）
- 放一个 Part 命名 `Base`（基地）

### 3. 搭白模地图
- 一块矩形地面，约 200x300 studs
- 简单颜色区分区域就行
- 不要求好看，结构清楚就行

### 4. 放路径点（最重要！）
在 PathNodes 文件夹里放 6 个 Part：
- Node1, Node2, Node3, Node4, Node5, Node6
- 从 SpawnPoint 附近开始，弯弯走到 Base
- 点和点之间距离 30-50 studs
- 最后一个 Node6 靠近 Base

### 5. 放塔位
在 TowerSpots 文件夹里放 4 个 Part：
- Spot1, Spot2, Spot3, Spot4
- 放在路径两侧，不要挡路
- 每个大小约 6x6 studs，颜色用绿色

### 6. 搭 ReplicatedStorage 目录
建这些 Folder：
- `Remotes`（以后放 RemoteEvent）
- `Config`（放配置表）
- `Units`（以后放塔模型）
- `Enemies`（以后放怪模型）

### 7. 搭 ServerScriptService 目录
建这些空 Script：
- `GameManager`（主控）
- `WaveManager`（波次）
- `EnemyService`（敌人）
- `UnitService`（塔）
今天里面可以是空的，只要文件在就行。

### 8. 搭 Config 配置表
在 ReplicatedStorage > Config 里建 3 个 ModuleScript：
- `UnitConfig`
- `EnemyConfig`
- `WaveConfig`
内容我已经写好了，直接复制粘贴（见下方）。

### 9. 搭 StarterGui 占位
建一个 ScreenGui 叫 `MainUI`，里面放：
- `CoinsLabel`（TextLabel，左上角，显示"金币: 200"）
- `WaveLabel`（TextLabel，顶部居中，显示"波次: 0/3"）
- `BaseHpLabel`（TextLabel，右上角，显示"基地: 20/20"）
- `PlaceTowerBtn`（TextButton，底部居中，显示"放置塔 $100"）

### 10. 测试验收
打开 Studio 跑一下，确认：
- [ ] 地图能看到
- [ ] 路径点顺序对
- [ ] 基地和出生点位置对
- [ ] UI 文字显示正常
- [ ] 文件夹结构整齐

---

## 今天禁止做的
- 不写移动逻辑
- 不写攻击逻辑
- 不做开蛋
- 不做商城
- 不做存档
- 不做第二张地图
- 不做花哨 UI

---

## 明天 Day 2 要做的（提前知道方向）
1. 写 Lag Blob 沿路径点移动
2. 到基地扣血
3. Toast Dog 自动攻击
4. 波次管理器刷怪
