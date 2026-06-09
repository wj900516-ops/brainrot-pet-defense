-- WaveService (ModuleScript)
-- 放在 ServerScriptService > Services > WaveService
-- Phase 9：波次进程 + 基地血量 + 失败条件（防御会话状态）。
-- Phase 14：分梯队难度 + Boss 里程碑（每 5 波）。
--
-- 职责（server-authoritative，本会话内存状态，不持久化）：
--   * 维护 waveNumber / baseHp / sessionFailed。
--   * 每波按"波次计划"生成敌人（数量/血量/速度/奖励随 tier 与 waveInTier 增长）；
--     每 5 波（5/10/15…）为 Boss 波：仅 1 个 Boss，更肉/更慢/奖励更高。
--   * 本波全部解决（击杀或逃逸）后，延迟开始下一波。
--   * 敌人逃逸（到达基地）→ 基地血量 -1（由 EnemyService.onEscaped 调用 OnEnemyEscaped）。
--   * 基地血量归 0 → 会话失败：停止刷怪、清理残余敌人。
--   * Phase 13：失败后可重开会话（ResetSession：清敌人 + 重置基地/波次/梯队 + 重启刷怪，代号防重复循环）。
--   * 在世界中用一块"基地状态板"（BillboardGui）显示 Wave / Tier / BOSS / Base HP / 失败状态，供 QA 可见。
--     —— 这是服务端创建的世界对象（自动复制），【不改 MainUI】、不新增 remote。
--
-- 难度全部派生自 waveNumber（确定性、可测试）：重开把 waveNumber 归 0 即清空所有梯队/Boss 状态。
-- 边界：只负责"会话/波次/基地"，把"敌人本身"交给 EnemyService。不发奖励（击杀奖励仍在 ServerInit）。

local Workspace = game:GetService("Workspace")

local EnemyService = require(script.Parent.EnemyService)

local WaveService = {}

-- ---------- 可调参数（Tuning Knobs） ----------
local INTER_WAVE_DELAY_SECONDS = 5 -- 两波之间的延迟
local SPAWN_STAGGER_SECONDS = 1 -- 同波内敌人之间的生成间隔
local BASE_MAX_HP = 10 -- 基地初始血量
local WAVES_PER_TIER = 5 -- 每 5 波一个梯队；第 5 波（5/10/15…）为 Boss 波
local NORMAL_ENEMY_ID = "LagBlob" -- 普通波敌人 id（EnemyConfig）
local BOSS_ENEMY_ID = "BossLagBlob" -- Boss 波敌人 id（EnemyConfig：更大/更肉/更高奖励）
local FALLBACK_BASE_POSITION = Vector3.new(0, 3, 0) -- 兜底（EnemyService 未提供时）

-- ---------- 波次难度计划（纯函数，确定性，可单测） ----------
-- 梯队结构：每 WAVES_PER_TIER(=5) 波为一梯队，第 5 波为 Boss 波。
--   tier        = floor((wave-1)/5) + 1   梯队号（1..）；越高越强
--   waveInTier  = ((wave-1) % 5) + 1       本梯队内第几波（1..5；5=Boss）
--   isBossWave  = wave % 5 == 0
local function getWaveTier(waveNumber)
	return math.floor((waveNumber - 1) / WAVES_PER_TIER) + 1
end
local function getWaveInTier(waveNumber)
	return ((waveNumber - 1) % WAVES_PER_TIER) + 1
end
local function isBossWave(waveNumber)
	return waveNumber % WAVES_PER_TIER == 0
end

-- 为某一波构建生成计划（敌人 id / 数量 / 倍率）。倍率会传给 EnemyService.SpawnEnemy。
--   普通波：数量 = 2 + waveInTier + tier；血量随 tier(+0.20) 与 waveInTier(+0.08) 增长；
--           速度随 tier 轻微增长(+0.03)；奖励不缩放（rewardMult=1）。
--   Boss 波：仅 1 个 Boss；血量倍率 4 + 1.25*tier；速度倍率 0.75 + 0.03*tier（比普通更慢）；
--           奖励倍率 5 + tier（显著更高）。倍率随 tier 增长 → 越后的 Boss 越强。
local function buildWavePlan(waveNumber)
	local tier = getWaveTier(waveNumber)
	local waveInTier = getWaveInTier(waveNumber)
	if isBossWave(waveNumber) then
		return {
			isBoss = true,
			enemyId = BOSS_ENEMY_ID,
			count = 1,
			hpMult = 4 + 1.25 * tier,
			speedMult = 0.75 + 0.03 * tier,
			rewardMult = 5 + tier,
			tier = tier,
			waveInTier = waveInTier,
		}
	end
	return {
		isBoss = false,
		enemyId = NORMAL_ENEMY_ID,
		count = 2 + waveInTier + tier,
		hpMult = 1 + 0.20 * (tier - 1) + 0.08 * (waveInTier - 1),
		speedMult = 1 + 0.03 * (tier - 1),
		rewardMult = 1,
		tier = tier,
		waveInTier = waveInTier,
	}
end

-- 暴露纯函数供单测/调试（不依赖运行时状态）。
WaveService.GetWaveTier = getWaveTier
WaveService.GetWaveInTier = getWaveInTier
WaveService.IsBossWave = isBossWave
WaveService.BuildWavePlan = buildWavePlan

-- ---------- 会话状态（内存，不持久化） ----------
local waveNumber = 0
local baseHp = BASE_MAX_HP
local sessionFailed = false
local started = false
local statusLabel = nil
local currentTier = 1 -- 当前波所属梯队（仅用于状态板显示）
local currentIsBoss = false -- 当前波是否为 Boss 波（仅用于状态板显示）
local generation = 0 -- 波次循环代号：每次启动 +1；旧循环检测到代号变化即退出（保证不重复循环）
local onSessionFailed = nil -- 会话失败时回调一次（供 ServerInit 推送客户端"可重开"状态）

-- ---------- 基地状态板（世界 Billboard，非 MainUI） ----------
local function buildStatusBoard()
	-- Phase 10：基地放在路径终点（最后一个航点）。EnemyService 未提供时回退到固定点。
	local basePos = FALLBACK_BASE_POSITION
	if EnemyService.GetBasePosition then
		local ok, pos = pcall(EnemyService.GetBasePosition)
		if ok and typeof(pos) == "Vector3" then
			basePos = pos
		end
	end

	local pad = Instance.new("Part")
	pad.Name = "BasePad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Size = Vector3.new(8, 1, 8)
	pad.Position = basePos - Vector3.new(0, 2, 0)
	pad.Color = Color3.fromRGB(70, 110, 200)
	pad.Transparency = 0.3
	pad.Material = Enum.Material.SmoothPlastic

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BaseStatus"
	billboard.Size = UDim2.fromOffset(360, 56) -- Phase 14：加宽以容纳 Tier/BOSS 文本
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true -- Phase 14：自适应，避免更长的 Tier/BOSS 文本溢出
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = ""
	label.Parent = billboard
	statusLabel = label

	pad.Parent = Workspace
end

local function updateStatus()
	if not statusLabel then
		return
	end
	if sessionFailed then
		statusLabel.Text = string.format("BASE DESTROYED  —  reached Wave %d", waveNumber)
		statusLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
	elseif currentIsBoss then
		statusLabel.Text = string.format("Wave %d · Tier %d · BOSS   |   Base HP %d/%d", waveNumber, currentTier, baseHp, BASE_MAX_HP)
		statusLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
	else
		statusLabel.Text = string.format("Wave %d · Tier %d   |   Base HP %d/%d", waveNumber, currentTier, baseHp, BASE_MAX_HP)
		statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	end
end

-- ---------- 公开 API ----------

-- 敌人逃逸（到达基地）→ 扣基地血量；归 0 则会话失败。由 EnemyService.onEscaped 调用。
-- 逃逸不发奖励（奖励只在击杀路径 onEnemyKilled 中发生）。
function WaveService.OnEnemyEscaped(_enemy)
	if sessionFailed then
		return
	end
	baseHp = math.max(0, baseHp - 1)
	warn(string.format("[WaveService] 敌人到达基地！Base HP %d/%d", baseHp, BASE_MAX_HP))
	updateStatus()

	if baseHp <= 0 then
		sessionFailed = true
		warn(string.format("[WaveService] 基地被摧毁，会话失败（到达第 %d 波）", waveNumber))
		updateStatus()
		EnemyService.ClearAll() -- 清理残余敌人
		if onSessionFailed then
			onSessionFailed() -- 通知 ServerInit（推送客户端"可重开"提示）
		end
	end
end

-- 只读查询（供调试 / 将来 UI）。
function WaveService.GetWave()
	return waveNumber
end
function WaveService.GetBaseHp()
	return baseHp
end
function WaveService.IsFailed()
	return sessionFailed
end
-- 当前波所属梯队（派生自 waveNumber；未开始时为初始值 1）。
function WaveService.GetTier()
	return currentTier
end
-- 当前波是否为 Boss 波。
function WaveService.IsBossWaveActive()
	return currentIsBoss
end

-- 波次循环（带代号）：每波生成 N → 等待全部解决 → 延迟 → 下一波。
-- 任意一处发现 myGen ~= generation（已被新循环取代）或 sessionFailed，立即退出。
local function runWaveLoop(myGen)
	while myGen == generation and not sessionFailed do
		waveNumber += 1
		local plan = buildWavePlan(waveNumber)
		currentTier = plan.tier
		currentIsBoss = plan.isBoss
		updateStatus()
		print(string.format(
			"[WaveService] 第 %d 波开始 — Tier %d / %s / 敌人 ×%d（hp×%.2f spd×%.2f reward×%.2f）",
			waveNumber,
			plan.tier,
			plan.isBoss and "BOSS 波" or "普通波",
			plan.count,
			plan.hpMult,
			plan.speedMult,
			plan.rewardMult
		))

		local spawnOptions = {
			hpMult = plan.hpMult,
			speedMult = plan.speedMult,
			rewardMult = plan.rewardMult,
			isBoss = plan.isBoss,
		}
		for _ = 1, plan.count do
			if myGen ~= generation or sessionFailed then
				break
			end
			EnemyService.SpawnEnemy(plan.enemyId, spawnOptions)
			task.wait(SPAWN_STAGGER_SECONDS)
		end

		while myGen == generation and not sessionFailed and #EnemyService.GetAliveEnemies() > 0 do
			task.wait(0.5)
		end

		if myGen ~= generation or sessionFailed then
			break
		end

		print(string.format("[WaveService] 第 %d 波结束，%ds 后开始下一波", waveNumber, INTER_WAVE_DELAY_SECONDS))
		task.wait(INTER_WAVE_DELAY_SECONDS)
	end
end

-- 启动一个新的波次循环：代号 +1（旧循环若仍在，会因代号变化而退出），保证同一时刻仅一个循环。
local function startWaveLoop()
	generation += 1
	local myGen = generation
	task.spawn(function()
		runWaveLoop(myGen)
	end)
end

-- 启动（幂等）。options.onSessionFailed() 可选：会话失败时回调一次。
function WaveService.Start(options)
	if started then
		return
	end
	started = true
	onSessionFailed = options and options.onSessionFailed

	buildStatusBoard()
	updateStatus()
	startWaveLoop()
end

-- 重开会话（仅在失败后允许）：清残余敌人 + 重置 baseHp/waveNumber + 清失败 + 重启刷怪。
-- 返回是否成功（运行中返回 false）。
-- 注意：塔的清理由 ServerInit 编排（TowerService.ClearAll），保持 WaveService 不依赖 TowerService。
function WaveService.ResetSession()
	if not sessionFailed then
		return false -- 运行中不允许重开
	end
	EnemyService.ClearAll() -- 清残余敌人（清后 alive=false，不再发奖/扣血）
	baseHp = BASE_MAX_HP
	waveNumber = 0
	currentTier = 1 -- 重置梯队显示（难度本就派生自 waveNumber，归 0 即清空所有梯队/Boss 状态）
	currentIsBoss = false
	sessionFailed = false
	updateStatus()
	startWaveLoop() -- 重新开始（代号 +1）
	return true
end

return WaveService
