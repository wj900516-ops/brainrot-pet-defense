-- WaveService (ModuleScript)
-- 放在 ServerScriptService > Services > WaveService
-- Phase 9：波次进程 + 基地血量 + 失败条件（防御会话状态）。
--
-- 职责（server-authoritative，本会话内存状态，不持久化）：
--   * 维护 waveNumber / baseHp / sessionFailed。
--   * 每波生成固定数量的 LagBlob；本波全部解决（击杀或逃逸）后，延迟开始下一波。
--   * 敌人逃逸（到达基地）→ 基地血量 -1（由 EnemyService.onEscaped 调用 OnEnemyEscaped）。
--   * 基地血量归 0 → 会话失败：停止刷怪、清理残余敌人。
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
local BASE_POSITION = Vector3.new(0, 3, 0) -- 与 EnemyService 的基地点一致

-- ---------- 会话状态（内存，不持久化） ----------
local waveNumber = 0
local baseHp = BASE_MAX_HP
local sessionFailed = false
local started = false
local statusLabel = nil

-- ---------- 基地状态板（世界 Billboard，非 MainUI） ----------
local function buildStatusBoard()
	local pad = Instance.new("Part")
	pad.Name = "BasePad"
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanQuery = false
	pad.Size = Vector3.new(8, 1, 8)
	pad.Position = BASE_POSITION - Vector3.new(0, 2, 0)
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

-- 启动波次循环（幂等）。每波：生成 N 个 → 等待全部解决 → 延迟 → 下一波；失败则停止。
function WaveService.Start()
	if started then
		return
	end
	started = true

	buildStatusBoard()
	updateStatus()

	task.spawn(function()
		while not sessionFailed do
			waveNumber += 1
			updateStatus()
			print(string.format("[WaveService] 第 %d 波开始（%d 个敌人）", waveNumber, ENEMIES_PER_WAVE))

			-- 生成本波敌人（轻微错峰，便于观察）。
			for _ = 1, ENEMIES_PER_WAVE do
				if sessionFailed then
					break
				end
				EnemyService.SpawnEnemy(ENEMY_ID)
				task.wait(SPAWN_STAGGER_SECONDS)
			end

			-- 等待本波全部解决（击杀或逃逸 → 无存活敌人），或会话失败。
			while not sessionFailed and #EnemyService.GetAliveEnemies() > 0 do
				task.wait(0.5)
			end

			if sessionFailed then
				break
			end

			print(string.format("[WaveService] 第 %d 波结束，%ds 后开始下一波", waveNumber, INTER_WAVE_DELAY_SECONDS))
			task.wait(INTER_WAVE_DELAY_SECONDS)
		end

		print(string.format("[WaveService] 会话失败，停止刷怪（到达第 %d 波）", waveNumber))
	end)
end

return WaveService
