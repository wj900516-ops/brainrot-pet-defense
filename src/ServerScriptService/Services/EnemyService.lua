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
local SPAWN_POSITION = Vector3.new(0, 3, -40) -- 敌人出生点（远端）
local BASE_POSITION = Vector3.new(0, 3, 0) -- 基地点（玩家出生附近）
local REACH_BASE_DISTANCE = 4 -- 距基地多近算"到达/逃逸"
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
	part.Position = SPAWN_POSITION

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
	}
	buildEnemyModel(enemy)
	updateHpLabel(enemy)
	table.insert(enemies, enemy)
	return enemy
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

-- 启动移动 + 清理循环（幂等）。options.onEscaped(enemy) 可选。
function EnemyService.Start(options)
	if started then
		return
	end
	started = true
	local onEscaped = options and options.onEscaped

	RunService.Heartbeat:Connect(function(dt)
		-- 移动 + 逃逸判定
		for _, enemy in ipairs(enemies) do
			if enemy.alive and enemy.model and enemy.model.Parent then
				local pos = enemy.model.Position
				local toBase = BASE_POSITION - pos
				local dist = toBase.Magnitude
				if dist <= REACH_BASE_DISTANCE then
					-- 到达基地 → 逃逸（本阶段无基地血量，直接移除）
					enemy.alive = false
					destroyEnemy(enemy)
					if onEscaped then
						onEscaped(enemy)
					end
				else
					local step = math.min(dist, enemy.speed * dt)
					local newPos = pos + (toBase.Unit * step)
					enemy.model.CFrame = CFrame.new(newPos, BASE_POSITION)
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
