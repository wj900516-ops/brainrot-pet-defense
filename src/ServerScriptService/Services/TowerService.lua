-- TowerService (ModuleScript)
-- 放在 ServerScriptService > Services > TowerService
-- Phase 11：塔放置（server-authoritative）。仅放置，不含战斗（Phase 12）。
--
-- 设计：客户端只发"放置意图"（不带位置）；服务端读取玩家角色位置并校验后放置。
--   → 客户端无法伪造位置 / 花费 / 拥有者 / 伤害；不能免费造塔。
--
-- 校验：金币足够、有角色、距路径航点不太近、距其它塔不太近。
-- 通过则扣金币 + 生成占位塔（世界 Anchored Part，自动复制）。失败安全拒绝、不扣币。
-- 塔仅存在于当前会话（不持久化）。

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)
local EnemyService = require(script.Parent.EnemyService)

local TowerService = {}

-- ---------- 可调参数 ----------
local MIN_DISTANCE_FROM_PATH = 8 -- 塔到任一路径航点的最小水平距离
local MIN_DISTANCE_BETWEEN_TOWERS = 8 -- 塔与塔之间的最小水平距离
local GROUND_DROP = 3 -- HRP 到脚下地面的近似高度（用于把塔放到地面）
local TOWERS_FOLDER_NAME = "Towers"

-- 内置兜底塔定义（TowerConfig 缺失时使用）。
local FALLBACK_TOWER = {
	id = "basic_tower",
	displayName = "Tower",
	cost = 100,
	size = Vector3.new(4, 8, 4),
	color = Color3.fromRGB(120, 130, 245),
}

-- ---------- 加载 TowerConfig（容错） ----------
local TowerConfig
do
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("TowerConfig")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			TowerConfig = result
		else
			warn("[TowerService] require TowerConfig 失败，使用内置兜底塔。错误：" .. tostring(result))
		end
	else
		warn("[TowerService] 未找到 ReplicatedStorage.Config.TowerConfig，使用内置兜底塔")
	end
end

local function getTowerDef()
	if TowerConfig and TowerConfig.GetBasicTower then
		local def = TowerConfig.GetBasicTower()
		if type(def) == "table" then
			return def
		end
	end
	return FALLBACK_TOWER
end

-- ---------- 运行时状态 ----------
local towers = {} -- 数组：{ model, position, ownerUserId }
local started = false

local function ensureFolder()
	local folder = Workspace:FindFirstChild(TOWERS_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = TOWERS_FOLDER_NAME
		folder.Parent = Workspace
	end
	return folder
end

-- 水平（忽略 Y）距离，便于地面高度不一致时稳健判定。
local function horizontalDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function tooCloseToPath(position)
	for _, node in ipairs(EnemyService.GetRoute()) do
		if horizontalDistance(node, position) < MIN_DISTANCE_FROM_PATH then
			return true
		end
	end
	return false
end

local function tooCloseToTower(position)
	for _, t in ipairs(towers) do
		if horizontalDistance(t.position, position) < MIN_DISTANCE_BETWEEN_TOWERS then
			return true
		end
	end
	return false
end

local function buildTowerModel(def, position)
	local size = (typeof(def.size) == "Vector3") and def.size or FALLBACK_TOWER.size
	local part = Instance.new("Part")
	part.Name = "Tower_" .. tostring(def.id or "basic")
	part.Anchored = true
	part.CanCollide = true
	part.Size = size
	part.Color = (typeof(def.color) == "Color3") and def.color or FALLBACK_TOWER.color
	part.Material = Enum.Material.SmoothPlastic
	part.Position = position

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(120, 24)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = (type(def.displayName) == "string" and def.displayName) or "Tower"
	label.Parent = billboard

	part.Parent = ensureFolder()
	return part
end

-- ---------- 公开 API ----------

-- 尝试为玩家在其角色位置放置一座塔。完全 server-authoritative。
-- 返回结果对象：{ success = bool, reason = string, cost = number? }
function TowerService.TryPlaceTower(player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return { success = false, reason = "no_data" }
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return { success = false, reason = "no_character" }
	end

	local def = getTowerDef()
	local cost = (type(def.cost) == "number" and def.cost >= 0) and def.cost or FALLBACK_TOWER.cost
	local size = (typeof(def.size) == "Vector3") and def.size or FALLBACK_TOWER.size

	-- 1) 金币足够？
	if (data.Coins or 0) < cost then
		return { success = false, reason = "not_enough_coins", cost = cost }
	end

	-- 2) 计算放置位置（塔底落在角色脚下地面）
	local groundY = hrp.Position.Y - GROUND_DROP
	local position = Vector3.new(hrp.Position.X, groundY + size.Y / 2, hrp.Position.Z)

	-- 3) 距路径不太近？
	if tooCloseToPath(position) then
		return { success = false, reason = "too_close_to_path", cost = cost }
	end

	-- 4) 距其它塔不太近？
	if tooCloseToTower(position) then
		return { success = false, reason = "too_close_to_tower", cost = cost }
	end

	-- 通过 → 扣币 + 建塔（顺序：先扣币，再建塔）
	PlayerDataService.AddCoins(player, -cost)
	local model = buildTowerModel(def, position)
	table.insert(towers, { model = model, position = position, ownerUserId = player.UserId })

	return { success = true, reason = "placed", cost = cost }
end

-- 移除某玩家拥有的塔（玩家离开时调用）。
local function clearPlayerTowers(player)
	for i = #towers, 1, -1 do
		if towers[i].ownerUserId == player.UserId then
			if towers[i].model then
				towers[i].model:Destroy()
			end
			table.remove(towers, i)
		end
	end
end

-- 启动（幂等）：建塔文件夹 + 玩家离开清理。
function TowerService.Start()
	if started then
		return
	end
	started = true
	ensureFolder()
	Players.PlayerRemoving:Connect(clearPlayerTowers)
end

return TowerService
