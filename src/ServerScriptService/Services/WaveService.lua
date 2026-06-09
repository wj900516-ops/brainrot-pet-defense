-- WaveService (ModuleScript)
-- 放在 ServerScriptService > Services > WaveService
-- Phase 9：波次进程 + 基地血量 + 失败条件（防御会话状态）。
--
-- 职责（server-authoritative，本会话内存状态，不持久化）：
--   * 维护 waveNumber / baseHp / sessionFailed。
--   * 每波生成固定数量的 LagBlob；本波全部解决（击杀或逃逸）后，延迟开始下一波。
--   * 敌人逃逸（到达基地）→ 基地血量 -1（由 EnemyService.onEscaped 调用 OnEnemyEscaped）。
--   * 基地血量归 0 → 会话失败：停止刷怪、清理残余敌人。
--   * Phase 13：失败后可重开会话（ResetSession：清敌人 + 重置基地/波次 + 重启刷怪，代号防重复循环）。
--   * 在世界中用一块"基地状态板"（BillboardGui）显示 Wave / Base HP / 失败状态，供 QA 可见。
--     —— 这是服务端创建的世界对象（自动复制），【不改 MainUI】、不新增 remote。
--
-- 边界：只负责"会话/波次/基地"，把"敌人本身"交给 EnemyService。不发奖励（击杀奖励仍在 ServerInit）。

local Workspace = game:GetService("Workspace")

local EnemyService = require(script.Parent.EnemyService)

local WaveService = {}

-- ---------- 可调参数（Tuning Knobs） ----------
local ENEMIES_PER_WAVE = 3 -- 每波固定敌人数（无难度曲线）
local INTER_WAVE_DELAY_SECONDS = 5 -- 两波之间的延迟
local SPAWN_STAGGER_SECONDS = 1 -- 同波内敌人之间的生成间隔
local BASE_MAX_HP = 10 -- 基地初始血量
local ENEMY_ID = "LagBlob" -- 本阶段只刷一种敌人
local FALLBACK_BASE_POSITION = Vector3.new(0, 3, 0) -- 兜底（EnemyService 未提供时）

-- ---------- 会话状态（内存，不持久化） ----------
local waveNumber = 0
local baseHp = BASE_MAX_HP
local sessionFailed = false
local started = false
local statusLabel = nil
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
	billboard.Size = UDim2.fromOffset(280, 56)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 7, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = pad

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
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
	else
		statusLabel.Text = string.format("Wave %d   |   Base HP %d/%d", waveNumber, baseHp, BASE_MAX_HP)
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

-- 波次循环（带代号）：每波生成 N → 等待全部解决 → 延迟 → 下一波。
-- 任意一处发现 myGen ~= generation（已被新循环取代）或 sessionFailed，立即退出。
local function runWaveLoop(myGen)
	while myGen == generation and not sessionFailed do
		waveNumber += 1
		updateStatus()
		print(string.format("[WaveService] 第 %d 波开始（%d 个敌人）", waveNumber, ENEMIES_PER_WAVE))

		for _ = 1, ENEMIES_PER_WAVE do
			if myGen ~= generation or sessionFailed then
				break
			end
			EnemyService.SpawnEnemy(ENEMY_ID)
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
	sessionFailed = false
	updateStatus()
	startWaveLoop() -- 重新开始（代号 +1）
	return true
end

return WaveService
