-- EnemyService (ModuleScript)
-- 放在 ServerScriptService > Services > EnemyService
-- Phase 8：敌人生命周期（生成 / 移动 / 受伤 / 死亡 / 逃逸）。
--
-- 职责（纯机制，server-authoritative）：
--   * 用代码生成占位敌人（Anchored Part，自动复制到客户端，无需 remote）。
--   * 敌人从出生点朝基地点直线移动。
--   * 维护 hp / maxHp / speed / reward / alive，提供受伤与列表查询 API。
--   * 到达基地 → 逃逸（移除；本阶段无基地血量）。
--
-- 边界：EnemyService 不发奖励、不感知玩家/宠物 —— 由 CombatService 决定谁造成伤害，
--       由 ServerInit 决定击杀奖励。EnemyService 只负责"敌人本身"。

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EnemyService = {}

-- ---------- 可调参数（Tuning Knobs） ----------
-- Phase 10：路径/航点（route）。优先使用 Workspace.EnemyPath 下的 Waypoint_* 部件（人工摆放）；
-- 缺失/不足时用内置兜底直线路径（spawn -> base），并在 Workspace.EnemyPath 下生成不可见调试航点。
local PATH_FOLDER_NAME = "EnemyPath"
local WAYPOINT_PREFIX = "Waypoint_"
local FALLBACK_SPAWN = Vector3.new(0, 3, -40) -- 兜底路径起点（敌人出生）
local FALLBACK_BASE = Vector3.new(0, 3, 0) -- 兜底路径终点（基地）
local FALLBACK_SEGMENTS = 4 -- 兜底直线分段（生成 5 个航点）
local REACH_WAYPOINT_DISTANCE = 3 -- 距航点多近算"已到达该航点"
local ENEMY_SIZE = Vector3.new(3, 3, 3)
local DEFAULT_ENEMY_ID = "LagBlob"

-- 内置兜底敌人定义（当 EnemyConfig 缺失/该 id 不存在时使用），保证不崩。
local FALLBACK_ENEMY = {
	displayName = "Enemy",
	health = 50,
	speed = 8,
	killReward = 10,
}

-- ---------- 加载 EnemyConfig（容错，绝不无限 yield） ----------
local EnemyConfig
do
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("EnemyConfig")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			EnemyConfig = result
		else
			warn("[EnemyService] require EnemyConfig 失败，使用内置兜底敌人。错误：" .. tostring(result))
		end
	else
		warn("[EnemyService] 未找到 ReplicatedStorage.Config.EnemyConfig，使用内置兜底敌人")
	end
end

local function resolveDef(enemyId)
	local def = EnemyConfig and EnemyConfig[enemyId] or nil
	if type(def) ~= "table" then
		def = FALLBACK_ENEMY
	end
	local maxHp = (type(def.health) == "number" and def.health > 0) and def.health or FALLBACK_ENEMY.health
	local speed = (type(def.speed) == "number" and def.speed > 0) and def.speed or FALLBACK_ENEMY.speed
	local reward = (type(def.killReward) == "number" and def.killReward >= 0) and def.killReward or FALLBACK_ENEMY.killReward
	local displayName = (type(def.displayName) == "string" and def.displayName ~= "") and def.displayName or enemyId
	return { maxHp = math.floor(maxHp), speed = speed, reward = math.floor(reward), displayName = displayName }
end

-- ---------- 运行时状态 ----------
local enemies = {} -- 数组：敌人记录
local nextEnemyNumber = 0
local started = false

-- ---------- 路径解析（route：有序 Vector3 航点数组） ----------
local route = nil
local routeResolved = false

-- 读取 Workspace.EnemyPath 下的 Waypoint_* 部件（按名称排序）。少于 2 个则视为无效（返回 nil）。
local function readWorkspacePath()
	local folder = Workspace:FindFirstChild(PATH_FOLDER_NAME)
	if not folder then
		return nil
	end
	local parts = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") and child.Name:sub(1, #WAYPOINT_PREFIX) == WAYPOINT_PREFIX then
			table.insert(parts, child)
		end
	end
	if #parts < 2 then
		return nil
	end
	table.sort(parts, function(a, b)
		return a.Name < b.Name
	end)
	local points = {}
	for _, part in ipairs(parts) do
		table.insert(points, part.Position)
	end
	return points
end

-- 构建兜底直线路径（spawn -> base），并在 Workspace.EnemyPath 下生成不可见调试航点。
local function buildFallbackPath()
	local folder = Workspace:FindFirstChild(PATH_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PATH_FOLDER_NAME
		folder.Parent = Workspace
	end
	local points = {}
	for i = 0, FALLBACK_SEGMENTS do
		local t = i / FALLBACK_SEGMENTS
		local pos = FALLBACK_SPAWN:Lerp(FALLBACK_BASE, t)
		table.insert(points, pos)

		-- 不可见调试航点（仅作标记/可选可视化；不参与碰撞/查询）。
		local marker = Instance.new("Part")
		marker.Name = string.format("%s%02d", WAYPOINT_PREFIX, i + 1)
		marker.Anchored = true
		marker.CanCollide = false
		marker.CanQuery = false
		marker.Size = Vector3.new(1, 1, 1)
		marker.Transparency = 1 -- 不可见
		marker.Position = pos
		marker.Parent = folder
	end
	return points
end

-- 解析路径（仅一次，memoized）。优先用 Workspace 航点，否则兜底直线。
local function resolveRoute()
	if routeResolved then
		return route
	end
	routeResolved = true
	local points = readWorkspacePath()
	if points then
		route = points
		print(string.format("[EnemyService] 使用 Workspace.%s 路径（%d 个航点）", PATH_FOLDER_NAME, #points))
	else
		route = buildFallbackPath()
		warn(string.format(
			"[EnemyService] 未找到有效 Workspace.%s，使用内置兜底直线路径（%d 个航点）",
			PATH_FOLDER_NAME,
			#route
		))
	end
	return route
end

-- ---------- 占位敌人模型 ----------
local COLOR_ALIVE = Color3.fromRGB(120, 200, 90)
local COLOR_HURT = Color3.fromRGB(230, 180, 70)

local function buildEnemyModel(enemy)
	local part = Instance.new("Part")
	part.Name = "Enemy_" .. enemy.enemyId .. "_" .. tostring(enemy.number)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = ENEMY_SIZE
	part.Color = COLOR_ALIVE
	part.Material = Enum.Material.SmoothPlastic
	-- 初始位置由 SpawnEnemy 设为路径第一个航点。

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(140, 28)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = billboard

	enemy.model = part
	enemy.hpLabel = label
	part.Parent = Workspace
end

local function updateHpLabel(enemy)
	if enemy.hpLabel then
		enemy.hpLabel.Text = string.format("%s  [%d/%d]", enemy.displayName, math.max(0, enemy.hp), enemy.maxHp)
	end
end

local function destroyEnemy(enemy)
	if enemy.model then
		enemy.model:Destroy()
		enemy.model = nil
	end
end

-- ---------- 公开 API ----------

-- 生成一个敌人，返回其记录。
function EnemyService.SpawnEnemy(enemyId)
	enemyId = (type(enemyId) == "string" and enemyId ~= "") and enemyId or DEFAULT_ENEMY_ID
	local def = resolveDef(enemyId)

	local r = resolveRoute()

	nextEnemyNumber += 1
	local enemy = {
		enemyId = enemyId,
		number = nextEnemyNumber,
		displayName = def.displayName,
		hp = def.maxHp,
		maxHp = def.maxHp,
		speed = def.speed,
		reward = def.reward,
		alive = true,
		targetIndex = 2, -- 生成在航点 1，朝航点 2 前进
	}
	buildEnemyModel(enemy)
	enemy.model.Position = r[1] -- 在路径起点（第一个航点）生成
	updateHpLabel(enemy)
	table.insert(enemies, enemy)
	return enemy
end

-- 返回基地位置（路径最后一个航点）。供 WaveService 放置基地状态板。
function EnemyService.GetBasePosition()
	local r = resolveRoute()
	return r[#r]
end

-- 对敌人造成伤害。返回 true 当且仅当这一击把它从存活打到死亡（保证击杀只结算一次）。
function EnemyService.DamageEnemy(enemy, amount)
	if not enemy or not enemy.alive then
		return false
	end
	amount = (type(amount) == "number" and amount > 0) and amount or 0
	enemy.hp = math.max(0, enemy.hp - amount)
	updateHpLabel(enemy)
	if enemy.model then
		enemy.model.Color = COLOR_HURT
	end
	if enemy.hp <= 0 then
		enemy.alive = false -- one-shot：死亡只触发一次
		destroyEnemy(enemy)
		return true
	end
	return false
end

-- 返回当前存活敌人的快照数组（调用方可安全遍历；对其调用 DamageEnemy 不影响本快照）。
function EnemyService.GetAliveEnemies()
	local out = {}
	for _, enemy in ipairs(enemies) do
		if enemy.alive and enemy.model and enemy.model.Parent then
			table.insert(out, enemy)
		end
	end
	return out
end

-- 清空所有敌人（Phase 9：会话失败时清理残余敌人）。不发奖励、不扣基地血量。
-- 注意：本函数可能在移动心跳的 onEscaped 回调中被调用（此时正以 ipairs 遍历 enemies），
-- 因此【不做结构性移除】，仅置 alive=false + 销毁模型；
-- 实际从数组移除交给 Start 心跳末尾的清理过程（反向 table.remove）安全完成。
function EnemyService.ClearAll()
	for _, enemy in ipairs(enemies) do
		enemy.alive = false
		destroyEnemy(enemy)
	end
end

-- 启动移动 + 清理循环（幂等）。options.onEscaped(enemy) 可选。
function EnemyService.Start(options)
	if started then
		return
	end
	started = true
	local onEscaped = options and options.onEscaped
	local r = resolveRoute()

	RunService.Heartbeat:Connect(function(dt)
		-- 沿航点移动 + 到达终点（最后一个航点）= 逃逸
		for _, enemy in ipairs(enemies) do
			if enemy.alive and enemy.model and enemy.model.Parent then
				local pos = enemy.model.Position
				local targetIndex = enemy.targetIndex or 2
				local target = r[targetIndex] or r[#r]
				local toTarget = target - pos
				local dist = toTarget.Magnitude

				if dist <= REACH_WAYPOINT_DISTANCE then
					if targetIndex >= #r then
						-- 到达最后一个航点（基地）→ 逃逸（触发 Phase 9 基地扣血，由 onEscaped 决定）
						enemy.alive = false
						destroyEnemy(enemy)
						if onEscaped then
							onEscaped(enemy)
						end
					else
						-- 到达中间航点 → 前进到下一个
						enemy.targetIndex = targetIndex + 1
					end
				else
					local step = math.min(dist, enemy.speed * dt)
					local newPos = pos + (toTarget.Unit * step)
					enemy.model.CFrame = CFrame.new(newPos, target)
				end
			end
		end

		-- 清理死亡记录（保持数组不无限增长）
		for i = #enemies, 1, -1 do
			if not enemies[i].alive then
				table.remove(enemies, i)
			end
		end
	end)
end

return EnemyService
