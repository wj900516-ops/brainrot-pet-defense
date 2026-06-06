-- DummyTargetService (ModuleScript)
-- 放在 ServerScriptService > Services > DummyTargetService
-- 训练假人 / Dummy Target：Phase 2 的最小真实游戏行动。
--
-- 职责（纯机制，server-authoritative）：
--   * 在 Workspace 中用代码生成一个可点击的训练假人。
--   * 处理点击命中（ClickDetector.MouseClick 是服务端事件）。
--   * 维护血量、命中反馈、击败后重生。
--   * 击败时通过 GameEventService.EnemyDefeated 广播事件。
--
-- 重要边界：
--   * 本服务【不】发放金币 / 经验 / 完成任务 —— 它只负责"假人被击败"这件事。
--   * 进度与奖励由监听 EnemyDefeated 的一方（ServerInit -> TaskService）决定。
--   * 所有血量逻辑在服务端，客户端无法直接造成伤害或加进度。

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local GameEventService = require(script.Parent.GameEventService)

local DummyTargetService = {}

-- ---------- 可调参数（Tuning Knobs） ----------
local ENEMY_ID = "TrainingDummy"
local MAX_HP = 3 -- 几次点击击败
local HIT_COOLDOWN = 0.2 -- 同一玩家两次有效命中的最小间隔（秒），防连点刷
local RESPAWN_DELAY = 1.5 -- 击败后多久重生（秒）
local SPAWN_POSITION = Vector3.new(0, 5, -12) -- 假人世界坐标（按地图微调）
local CLICK_DISTANCE = 32 -- ClickDetector 最大激活距离（仅客户端便利，不可信）
-- 服务端独立的距离校验上限。不可仅依赖 ClickDetector.MaxActivationDistance（客户端可被篡改）。
-- 比 CLICK_DISTANCE 略大，留出"角色到假人表面"与"中心点"的余量，避免误杀正常边缘点击。
local MAX_VALID_HIT_DISTANCE = 40

-- ---------- 运行时状态 ----------
local dummyPart = nil
local hpLabel = nil
local hp = MAX_HP
local alive = false
local lastHitByPlayer = {} -- [player] = os.clock()，用于每玩家命中冷却
local started = false

-- ---------- 视觉 ----------
local COLOR_ALIVE = Color3.fromRGB(214, 72, 72)
local COLOR_HIT = Color3.fromRGB(255, 196, 96)
local COLOR_DEFEATED = Color3.fromRGB(90, 90, 100)

local function updateHpLabel()
	if hpLabel then
		hpLabel.Text = alive and string.format("Training Dummy  [%d/%d]", hp, MAX_HP) or "Defeated…"
	end
end

local function buildDummy()
	local part = Instance.new("Part")
	part.Name = ENEMY_ID
	part.Anchored = true
	part.CanCollide = true
	part.Size = Vector3.new(4, 6, 2)
	part.Position = SPAWN_POSITION
	part.Material = Enum.Material.SmoothPlastic
	part.Color = COLOR_ALIVE

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(180, 40)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = billboard
	hpLabel = label

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = CLICK_DISTANCE
	clickDetector.Parent = part
	clickDetector.MouseClick:Connect(function(playerWhoClicked)
		DummyTargetService.HandleHit(playerWhoClicked)
	end)

	part.Parent = Workspace
	dummyPart = part
end

local function flashHit()
	if not dummyPart then
		return
	end
	dummyPart.Color = COLOR_HIT
	local token = os.clock()
	dummyPart:SetAttribute("FlashToken", token)
	task.delay(0.1, function()
		if dummyPart and alive and dummyPart:GetAttribute("FlashToken") == token then
			dummyPart.Color = COLOR_ALIVE
		end
	end)
end

local function respawn()
	hp = MAX_HP
	alive = true
	if dummyPart then
		dummyPart.Color = COLOR_ALIVE
	end
	updateHpLabel()
end

-- 服务端距离校验：从玩家角色的 HumanoidRootPart 到假人位置的实际距离。
-- 不信任 ClickDetector.MaxActivationDistance（仅客户端便利）。距离过远则判定无效命中。
local function isWithinValidRange(player)
	if not dummyPart then
		return false
	end
	local character = player.Character
	if not character then
		return false
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	local distance = (hrp.Position - dummyPart.Position).Magnitude
	return distance <= MAX_VALID_HIT_DISTANCE
end

-- ---------- 公开 API ----------

-- 处理一次命中（由 ClickDetector 在服务端调用）。
-- 仅做：距离校验 -> 冷却校验 -> 扣血 -> 反馈 -> 击败时广播 EnemyDefeated。
function DummyTargetService.HandleHit(player)
	if not alive or not player then
		return
	end

	-- 服务端距离校验：拒绝来自过远位置的命中（防伪造/瞬移点击）。不通过则不加任何进度。
	if not isWithinValidRange(player) then
		return
	end

	-- 每玩家命中冷却，防止连点刷进度/刷事件
	local now = os.clock()
	local last = lastHitByPlayer[player]
	if last and (now - last) < HIT_COOLDOWN then
		return
	end
	lastHitByPlayer[player] = now

	hp -= 1
	flashHit()
	updateHpLabel()

	-- 可选事件：每次有效命中（未击败）。不发放任何奖励，仅作通知。
	GameEventService.TargetInteracted:Fire(player, ENEMY_ID)

	if hp <= 0 then
		-- 关键：先置 alive=false，保证击败事件每条命只广播一次（防止收尾连点重复触发）
		alive = false
		if dummyPart then
			dummyPart.Color = COLOR_DEFEATED
		end
		updateHpLabel()

		-- 广播"敌人被击败"——由监听方（ServerInit）决定进度与奖励
		GameEventService.EnemyDefeated:Fire(player, ENEMY_ID)

		task.delay(RESPAWN_DELAY, respawn)
	end
end

-- 生成假人并开始运行（幂等，重复调用无副作用）。
function DummyTargetService.Start(options)
	if started then
		return
	end
	started = true

	options = options or {}
	if options.position then
		SPAWN_POSITION = options.position
	end

	buildDummy()
	respawn() -- 初始化血量/状态并刷新文字

	-- 玩家离开时清理其命中冷却记录，避免 lastHitByPlayer 长期累积。
	Players.PlayerRemoving:Connect(function(player)
		lastHitByPlayer[player] = nil
	end)
end

return DummyTargetService
