-- TowerPlacer (LocalScript)
-- 放在 StarterGui > TowerPlacer > TowerPlacer (.client.lua => 客户端 LocalScript)
-- Phase 11.5：塔放置鬼影预览（ghost preview）。
--   * 按 T 进入放置模式，鼠标处显示半透明鬼影塔，随鼠标移动。
--   * 绿色=（客户端近似）可放置，红色=不可放置（近路径/近塔/太远）。
--   * 左键确认：把"地面落点"发给服务端；服务端最终校验并扣币放置。
--   * Esc / 右键取消放置模式。
-- 客户端只发位置意图，不发花费/拥有者/属性/奖励；服务端是唯一真相（再次完整校验）。
-- 纯代码 UI（独立 ScreenGui），不改 MainUI。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local towerRemote = Net.TowerRemote()

-- ---------- 与服务端一致的近似校验参数（仅 UX；服务端为准） ----------
local MIN_DISTANCE_FROM_PATH = 8
local MIN_DISTANCE_BETWEEN_TOWERS = 8
local MAX_PLACE_DISTANCE = 60

-- ---------- 塔尺寸/花费（读 TowerConfig，失败兜底） ----------
local TOWER_SIZE = Vector3.new(4, 8, 4)
local TOWER_COST = 100
do
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("TowerConfig")
	if module then
		local ok, TowerConfig = pcall(require, module)
		if ok and type(TowerConfig) == "table" and TowerConfig.GetBasicTower then
			local def = TowerConfig.GetBasicTower()
			if type(def) == "table" then
				if typeof(def.size) == "Vector3" then
					TOWER_SIZE = def.size
				end
				if type(def.cost) == "number" then
					TOWER_COST = def.cost
				end
			end
		end
	end
end

-- ===================== 反馈 UI（独立 ScreenGui，非 MainUI） =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TowerPlacerUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 90
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -16)
hint.Size = UDim2.fromOffset(360, 28)
hint.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
hint.BackgroundTransparency = 0.25
hint.TextColor3 = Color3.fromRGB(220, 224, 240)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 14
hint.Text = string.format("Press T to place a Tower (%d coins)", TOWER_COST)
hint.Parent = screenGui
local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 6)
hintCorner.Parent = hint

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -52)
toast.Size = UDim2.fromOffset(320, 28)
toast.BackgroundTransparency = 1
toast.TextColor3 = Color3.fromRGB(126, 244, 162)
toast.Font = Enum.Font.GothamBold
toast.TextSize = 16
toast.Text = ""
toast.Parent = screenGui

local toastToken = 0
local function showToast(text, isError)
	toast.Text = text
	toast.TextColor3 = isError and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(126, 244, 162)
	toastToken += 1
	local myToken = toastToken
	task.delay(2, function()
		if myToken == toastToken then
			toast.Text = ""
		end
	end)
end

local REASON_TEXT = {
	placed = "Tower placed!",
	not_enough_coins = "Not enough coins",
	too_close_to_path = "Too close to the path",
	too_close_to_tower = "Too close to another tower",
	too_far = "Too far away",
	too_high = "Placement too high",
	too_low = "Placement too low",
	bad_position = "Invalid placement position",
	no_character = "Cannot place right now",
	no_data = "Cannot place right now",
}

-- ===================== 鬼影预览 =====================
local COLOR_VALID = Color3.fromRGB(90, 230, 120)
local COLOR_INVALID = Color3.fromRGB(235, 90, 90)

local ghost = nil
local placementMode = false
local renderConn = nil

local function ensureGhost()
	if ghost then
		return ghost
	end
	local part = Instance.new("Part")
	part.Name = "TowerGhost"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- 不被鼠标射线命中
	part.Transparency = 0.55
	part.Size = TOWER_SIZE
	part.Material = Enum.Material.ForceField
	part.Color = COLOR_VALID
	ghost = part
	return part
end

local function horizontalDistance(a, b)
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- 点到线段（XZ）的最近距离（与服务端一致，仅 UX 近似）。
local function distancePointToSegmentXZ(point, a, b)
	local px, pz = point.X, point.Z
	local ax, az = a.X, a.Z
	local bx, bz = b.X, b.Z
	local dx, dz = bx - ax, bz - az
	local segLenSq = dx * dx + dz * dz
	local t
	if segLenSq <= 1e-6 then
		t = 0
	else
		t = math.clamp(((px - ax) * dx + (pz - az) * dz) / segLenSq, 0, 1)
	end
	local cx, cz = ax + t * dx, az + t * dz
	local ex, ez = px - cx, pz - cz
	return math.sqrt(ex * ex + ez * ez)
end

-- 取按自然数字顺序排序后的路径点（镜像服务端排序，使 UX 段判定与服务端一致）。
local function trailingNumber(name)
	local s = string.match(name, "(%d+)%s*$")
	return s and tonumber(s) or math.huge
end
local function sortedPathPoints()
	local folder = Workspace:FindFirstChild("PathNodes") or Workspace:FindFirstChild("EnemyPath")
	if not folder then
		return {}
	end
	local items = {}
	for _, n in ipairs(folder:GetChildren()) do
		if n:IsA("BasePart") then
			table.insert(items, n)
		end
	end
	table.sort(items, function(a, b)
		local na, nb = trailingNumber(a.Name), trailingNumber(b.Name)
		if na ~= nb then
			return na < nb
		end
		return a.Name < b.Name
	end)
	local pts = {}
	for _, n in ipairs(items) do
		table.insert(pts, n.Position)
	end
	return pts
end

-- 相机射线 → 地面落点（排除鬼影、自身角色、Towers，以投影到地面）。
local function mouseGroundPoint()
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local mpos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mpos.X, mpos.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = {}
	if ghost then
		table.insert(exclude, ghost)
	end
	if player.Character then
		table.insert(exclude, player.Character)
	end
	local towersFolder = Workspace:FindFirstChild("Towers")
	if towersFolder then
		table.insert(exclude, towersFolder)
	end
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1200, params)
	return result and result.Position or nil
end

-- 客户端近似校验（仅 UX；服务端为准）：距玩家、距路径节点、距已有塔。
local function approxValid(groundPoint)
	if not groundPoint then
		return false
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	if horizontalDistance(groundPoint, hrp.Position) > MAX_PLACE_DISTANCE then
		return false
	end
	-- 距路径：逐段（Node_i -> Node_{i+1}）检查，使 ghost 在路面（节点之间）也变红。
	local pts = sortedPathPoints()
	if #pts == 1 then
		if horizontalDistance(pts[1], groundPoint) < MIN_DISTANCE_FROM_PATH then
			return false
		end
	else
		for i = 1, #pts - 1 do
			if distancePointToSegmentXZ(groundPoint, pts[i], pts[i + 1]) < MIN_DISTANCE_FROM_PATH then
				return false
			end
		end
	end
	local towersFolder = Workspace:FindFirstChild("Towers")
	if towersFolder then
		for _, t in ipairs(towersFolder:GetChildren()) do
			if t:IsA("BasePart") and horizontalDistance(t.Position, groundPoint) < MIN_DISTANCE_BETWEEN_TOWERS then
				return false
			end
		end
	end
	return true
end

local function updateGhost()
	local g = ensureGhost()
	local groundPoint = mouseGroundPoint()
	if not groundPoint then
		g.Transparency = 1 -- 没有落点时隐藏
		return
	end
	g.Transparency = 0.55
	g.Position = groundPoint + Vector3.new(0, TOWER_SIZE.Y / 2, 0)
	g.Color = approxValid(groundPoint) and COLOR_VALID or COLOR_INVALID
end

local function enterPlacement()
	if placementMode then
		return
	end
	placementMode = true
	local g = ensureGhost()
	g.Parent = Workspace
	hint.Text = "Click to place  |  Esc / right-click to cancel"
	renderConn = RunService.RenderStepped:Connect(updateGhost)
	print("[TowerPlacer] placement mode: ON")
end

local function exitPlacement()
	if not placementMode then
		return
	end
	placementMode = false
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if ghost then
		ghost.Parent = nil
	end
	hint.Text = string.format("Press T to place a Tower (%d coins)", TOWER_COST)
	print("[TowerPlacer] placement mode: OFF")
end

local function confirmPlacement()
	local groundPoint = mouseGroundPoint()
	if not groundPoint then
		return
	end
	-- 只发位置意图；服务端最终校验并扣币。即使客户端近似为红，也由服务端决定（这里直接交给服务端）。
	towerRemote:FireServer("PlaceTower", groundPoint)
	exitPlacement()
end

-- ===================== 接线 =====================
towerRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Result" then
		local reason = payload and payload.reason or "no_data"
		local ok = payload and payload.success == true
		showToast(REASON_TEXT[reason] or (ok and "Tower placed!" or "Placement failed"), not ok)
		print("[TowerPlacer] result:", reason, "success=", tostring(ok))
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		if placementMode then
			exitPlacement()
		else
			enterPlacement()
		end
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if placementMode then
			exitPlacement()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		if placementMode then
			confirmPlacement()
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if placementMode then
			exitPlacement()
		end
	end
end)

print("[TowerPlacer] loaded — press T to enter placement mode")
