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
local MAX_PLACE_DISTANCE = 60 -- Phase 11.5：放置点距玩家的最大水平距离（防跨地图放置）
local VERTICAL_BAND = 30 -- Phase 11.5：放置点 Y 相对玩家的允许范围（防离谱高度）
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

-- 有限实数校验：拒绝 NaN（n ~= n）与 ±Inf。
local function isFiniteNumber(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- 有限 Vector3 校验：必须是 Vector3 且 X/Y/Z 全为有限实数。
local function isFiniteVector3(v)
	return typeof(v) == "Vector3" and isFiniteNumber(v.X) and isFiniteNumber(v.Y) and isFiniteNumber(v.Z)
end

-- 水平（忽略 Y）距离，便于地面高度不一致时稳健判定。
local function horizontalDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- 点到线段（XZ 平面）的最近距离：把 point 投影到段 AB，t 夹到 [0,1]，返回到最近点的 XZ 距离。
local function distancePointToSegmentXZ(point, a, b)
	local px, pz = point.X, point.Z
	local ax, az = a.X, a.Z
	local bx, bz = b.X, b.Z
	local dx, dz = bx - ax, bz - az
	local segLenSq = dx * dx + dz * dz
	local t
	if segLenSq <= 1e-6 then
		t = 0 -- A、B 几乎重合：退化为到 A 的距离
	else
		t = ((px - ax) * dx + (pz - az) * dz) / segLenSq
		t = math.clamp(t, 0, 1)
	end
	local cx, cz = ax + t * dx, az + t * dz
	local ex, ez = px - cx, pz - cz
	return math.sqrt(ex * ex + ez * ez)
end

-- 校验"最终塔位"是否离敌人路线（整条折线，而非仅航点）太近。
-- 逐段检查 Node_i -> Node_{i+1}，使用 XZ 距离。任一段过近即拒绝。
local function tooCloseToPath(position)
	local route = EnemyService.GetRoute()
	if #route == 0 then
		return false
	end
	if #route == 1 then
		return horizontalDistance(route[1], position) < MIN_DISTANCE_FROM_PATH
	end
	for i = 1, #route - 1 do
		if distancePointToSegmentXZ(position, route[i], route[i + 1]) < MIN_DISTANCE_FROM_PATH then
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

-- 尝试为玩家放置一座塔。完全 server-authoritative。
-- requestedPosition（可选，Vector3）：客户端鬼影预览的地面落点；为空则回退到玩家脚下。
--   服务端始终对该位置做完整校验（不信任客户端）：距玩家不太远、竖直在合理范围、
--   金币足够、距路径/距塔不太近。
-- 返回结果对象：{ success = bool, reason = string, cost = number? }
function TowerService.TryPlaceTower(player, requestedPosition)
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

	-- 校验客户端位置（若提供）：必须是有限的 Vector3（拒绝 NaN / ±Inf / 非 Vector3）。
	-- 该校验先于任何距离/路径/金币/放置判定。
	if requestedPosition ~= nil and not isFiniteVector3(requestedPosition) then
		return { success = false, reason = "bad_position" }
	end

	-- 决定地面参考点：提供了合法位置则用之，否则回退玩家脚下（向后兼容）。
	local groundPoint
	if isFiniteVector3(requestedPosition) then
		groundPoint = requestedPosition
	else
		groundPoint = Vector3.new(hrp.Position.X, hrp.Position.Y - GROUND_DROP, hrp.Position.Z)
	end

	-- 反作弊 1：放置点距玩家不能太远（防跨地图放置）。
	if horizontalDistance(groundPoint, hrp.Position) > MAX_PLACE_DISTANCE then
		return { success = false, reason = "too_far", cost = cost }
	end

	-- 反作弊 2：竖直方向限制 —— 超出允许带宽直接【拒绝】（不夹紧、不强行放置）。
	if groundPoint.Y > hrp.Position.Y + VERTICAL_BAND then
		return { success = false, reason = "too_high", cost = cost }
	end
	if groundPoint.Y < hrp.Position.Y - VERTICAL_BAND then
		return { success = false, reason = "too_low", cost = cost }
	end

	-- 金币足够？
	if (data.Coins or 0) < cost then
		return { success = false, reason = "not_enough_coins", cost = cost }
	end

	-- 最终塔中心（塔底落在地面参考点）。
	local position = Vector3.new(groundPoint.X, groundPoint.Y + size.Y / 2, groundPoint.Z)

	-- 距路径不太近？
	if tooCloseToPath(position) then
		return { success = false, reason = "too_close_to_path", cost = cost }
	end
	-- 距其它塔不太近？
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
