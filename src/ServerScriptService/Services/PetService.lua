-- PetService (ModuleScript)
-- 放在 ServerScriptService > Services > PetService
-- 起始宠物 + 简单攻击循环（Phase 5，Option A）。
--
-- 职责（纯机制，server-authoritative）：
--   * 为每位玩家生成一只占位起始宠物（代码构建，无需美术）。
--   * 让宠物在主人附近跟随。
--   * 按攻击间隔在服务端调用 DummyTargetService.HandleHit(owner)。
--
-- Option A 设计：复用既有 DummyTargetService.HandleHit(owner)，不修改 DummyTargetService。
--   HandleHit 内部已自带"假人存活 / 主人距离 / 每玩家冷却"校验并在不满足时静默 no-op，
--   因此宠物只在【主人位于假人有效范围内】时才能真正命中（符合 Option A）。
--
-- 重要边界：
--   * PetService 【不】发放金币 / 经验 / 任务进度 / 奖励。它只触发"对假人的一次命中"。
--   * 进度与奖励仍由既有链路决定：HandleHit → EnemyDefeated → ServerInit → TaskService。

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DummyTargetService = require(script.Parent.DummyTargetService)
local PlayerDataService = require(script.Parent.PlayerDataService)

local PetService = {}

-- ---------- 加载 PetConfig（容错，绝不无限 yield） ----------
local function loadPetConfig()
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("PetConfig")
	if not module then
		warn("[PetService] 未找到 ReplicatedStorage.Config.PetConfig，使用内置兜底宠物")
		return nil
	end
	local ok, result = pcall(require, module)
	if ok and type(result) == "table" then
		return result
	end
	warn("[PetService] require PetConfig 失败，使用内置兜底宠物。错误：" .. tostring(result))
	return nil
end

local PetConfig = loadPetConfig()

-- 把原始宠物定义规范化为安全可用的表（缺字段/坏字段都有缺省）。
local function normalizeDef(def)
	def = type(def) == "table" and def or {}
	local visual = type(def.visual) == "table" and def.visual or {}
	return {
		id = type(def.id) == "string" and def.id or "starter_fallback",
		displayName = type(def.displayName) == "string" and def.displayName or "Pet",
		attackInterval = (type(def.attackInterval) == "number" and def.attackInterval > 0) and def.attackInterval or 2.25,
		followOffset = (typeof(def.followOffset) == "Vector3") and def.followOffset or Vector3.new(3, 2, 3),
		followStiffness = (type(def.followStiffness) == "number") and math.clamp(def.followStiffness, 0.01, 1) or 0.15,
		size = (typeof(visual.size) == "Vector3") and visual.size or Vector3.new(1.6, 1.6, 1.6),
		color = (typeof(visual.color) == "Color3") and visual.color or Color3.fromRGB(245, 205, 120),
		material = (typeof(visual.material) == "EnumItem") and visual.material or Enum.Material.SmoothPlastic,
	}
end

local function getStarterDef()
	local raw = PetConfig and PetConfig.GetStarterPet and PetConfig.GetStarterPet() or nil
	return normalizeDef(raw)
end

-- 按 petId 解析规范化定义；找不到返回 nil（由调用方决定兜底）。
local function getDefByPetId(petId)
	if PetConfig and PetConfig.GetPet then
		local raw = PetConfig.GetPet(petId)
		if type(raw) == "table" then
			return normalizeDef(raw)
		end
	end
	return nil
end

-- 返回起始宠物 id（供 ServerInit 调用 EnsureStarterPet）。
function PetService.GetStarterPetId()
	if PetConfig and type(PetConfig.StarterPetId) == "string" then
		return PetConfig.StarterPetId
	end
	return "starter_toast"
end

-- ---------- 运行时状态 ----------
-- [player] = { model = Part, def = normalizedDef, lastAttack = number }
local petsByPlayer = {}
local started = false

-- ---------- 占位宠物模型 ----------
local function buildPetModel(def, player)
	local part = Instance.new("Part")
	part.Name = "Pet_" .. tostring(player.UserId)
	part.Anchored = true -- 锚定：用 CFrame 直接驱动跟随，不走物理
	part.CanCollide = false
	part.CanQuery = false
	part.Shape = Enum.PartType.Ball
	part.Size = def.size
	part.Color = def.color
	part.Material = def.material

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(120, 28)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.5
	label.Text = def.displayName
	label.Parent = billboard

	part.Parent = Workspace
	return part
end

-- ---------- 公开 API ----------

-- 为玩家生成"已装备"的宠物（幂等：已存在则不重复生成）。
-- 数据驱动：从 PlayerDataService 读取已装备宠物，再用 PetConfig 解析视觉。
-- 不再隐式假设每位玩家都有 Toasty —— 必须由 PlayerDataService 已授予/装备。
function PetService.SpawnPet(player)
	if petsByPlayer[player] then
		return
	end

	-- 取已装备宠物（单宠物：取第一只）。EnsureStarterPet 应已保证存在。
	local entries = PlayerDataService.GetEquippedPetEntries(player)
	local entry = entries[1]
	if not entry then
		warn(string.format("[PetService] 玩家 %s 无已装备宠物，跳过生成", player.Name))
		return
	end

	-- 按 petId 解析视觉；petId 过时（配置中不存在）→ 告警并用起始视觉兜底。
	local def = getDefByPetId(entry.petId)
	if not def then
		warn(string.format(
			"[PetService] petId '%s' 在 PetConfig 中不存在，使用起始视觉兜底",
			tostring(entry.petId)
		))
		def = getStarterDef()
	end

	local model = buildPetModel(def, player)

	-- 初始位置：若角色已就绪则放在主人旁边，否则先放原点附近，等心跳循环拉过去。
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if hrp then
		model.Position = hrp.Position + def.followOffset
	end

	petsByPlayer[player] = { model = model, def = def, lastAttack = 0 }
end

-- 销毁玩家宠物并清理其状态（幂等）。
function PetService.DespawnPet(player)
	local pet = petsByPlayer[player]
	if not pet then
		return
	end
	if pet.model then
		pet.model:Destroy()
	end
	petsByPlayer[player] = nil
end

-- 启动宠物系统（幂等）：单个 Heartbeat 驱动所有宠物的跟随与攻击。
function PetService.Start()
	if started then
		return
	end
	started = true

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for player, pet in pairs(petsByPlayer) do
			local model = pet.model
			if model and model.Parent then
				-- 跟随：朝 "主人 HRP + 偏移" 平滑插值；无角色/HRP 时原地等待。
				local character = player.Character
				local hrp = character and character:FindFirstChild("HumanoidRootPart")
				if hrp then
					local target = hrp.Position + pet.def.followOffset
					local newPos = model.Position:Lerp(target, pet.def.followStiffness)
					model.CFrame = CFrame.new(newPos, hrp.Position)
				end

				-- 攻击：按间隔调用 HandleHit(owner)。HandleHit 自带存活/距离/冷却校验，
				-- 不满足条件时静默 no-op（即 Option A：仅主人在范围内才真正命中）。
				if (now - pet.lastAttack) >= pet.def.attackInterval then
					pet.lastAttack = now
					DummyTargetService.HandleHit(player)
				end
			end
		end
	end)

	-- 玩家离开时清理宠物（PetService 自身负责，符合 Phase 5 要求）。
	Players.PlayerRemoving:Connect(function(player)
		PetService.DespawnPet(player)
	end)
end

return PetService
