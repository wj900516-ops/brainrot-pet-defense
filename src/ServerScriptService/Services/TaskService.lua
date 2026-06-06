-- TaskService (ModuleScript)
-- 放在 ServerScriptService > Services > TaskService
-- 任务服务（Phase 3：配置驱动 + 起始任务链 + 事件匹配）。
-- 依赖：RewardService、PlayerDataService、ReplicatedStorage.Config.TaskConfig。
-- 不感知 Remote —— 由 ServerInit 负责把结果推送给客户端。
--
-- 设计要点：
--   * 任务定义来自 TaskConfig（数据驱动），并在加载时做防御式校验（容忍坏配置不崩服）。
--   * 每位玩家跟踪：当前在链中的下标 chainIndex、当前任务定义 def、当前进度 progress。
--   * 完成任务后推进到链的下一个；链结束则循环可重复 fallback。
--   * 事件匹配：仅当当前任务 type/target 与事件匹配时才加进度。
--   * 对外只暴露"公开任务数据"（title/progress/goal/rewardCoins/rewardXP），与 MainUI 兼容。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent.PlayerDataService)
local RewardService = require(script.Parent.RewardService)

local TaskService = {}

-- ---------- 防御性默认值 ----------
local DEFAULT_GOAL = 1

-- 内置兜底任务：当 TaskConfig 完全不可用 / 链为空时使用，保证游戏循环不中断。
local FALLBACK_TASK = {
	id = "fallback_defeat_dummy",
	type = "DefeatEnemy",
	target = "TrainingDummy",
	title = "Defeat a Training Dummy",
	goal = 1,
	rewardCoins = 0,
	rewardXP = 0,
}

-- ---------- 加载并校验配置（容错，且绝不无限 yield） ----------
-- 使用 FindFirstChild 而非 WaitForChild：若 Config / TaskConfig 缺失，
-- 直接告警并回退到内置兜底任务，服务端启动不会因缺配置而挂起。
local TaskConfig
do
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	local configModule = configFolder and configFolder:FindFirstChild("TaskConfig")

	if not configModule then
		warn("[TaskService] 未找到 ReplicatedStorage.Config.TaskConfig，使用内置兜底任务")
		TaskConfig = nil
	else
		local ok, result = pcall(require, configModule)
		if ok and type(result) == "table" then
			TaskConfig = result
		else
			warn("[TaskService] require TaskConfig 失败，使用内置兜底任务。错误：" .. tostring(result))
			TaskConfig = nil
		end
	end
end

-- 把一条原始配置规范化为安全的内部任务定义；非法则返回 nil（并告警）。
local function sanitizeDef(def)
	if type(def) ~= "table" then
		warn("[TaskService] 跳过非表类型的任务定义")
		return nil
	end

	local id = def.id
	if type(id) ~= "string" or id == "" then
		warn("[TaskService] 任务定义缺少合法 'id'，已跳过")
		return nil
	end

	local goal = def.goal
	if type(goal) ~= "number" or goal < 1 then
		warn(string.format("[TaskService] 任务 '%s' 的 goal 非法，回退为 %d", id, DEFAULT_GOAL))
		goal = DEFAULT_GOAL
	end
	goal = math.floor(goal)

	local taskType = (type(def.type) == "string" and def.type ~= "") and def.type or "DefeatEnemy"
	if type(def.type) ~= "string" or def.type == "" then
		warn(string.format("[TaskService] 任务 '%s' 缺少 type，回退为 'DefeatEnemy'", id))
	end

	local rewardCoins = type(def.rewardCoins) == "number" and def.rewardCoins or 0
	local rewardXP = type(def.rewardXP) == "number" and def.rewardXP or 0
	if type(def.rewardCoins) ~= "number" or type(def.rewardXP) ~= "number" then
		warn(string.format("[TaskService] 任务 '%s' 的 reward 缺失/非法，缺省为 0", id))
	end

	local title = (type(def.title) == "string" and def.title ~= "") and def.title or id

	return {
		id = id,
		type = taskType,
		target = def.target, -- 可能为 nil（非敌人类任务）
		title = title,
		goal = goal,
		rewardCoins = rewardCoins,
		rewardXP = rewardXP,
	}
end

-- 构建"已校验"的任务链；为空则使用内置兜底任务。
local function buildChain()
	local chain = {}
	local source = TaskConfig and TaskConfig.StarterChain
	if type(source) == "table" then
		for _, def in ipairs(source) do
			local clean = sanitizeDef(def)
			if clean then
				table.insert(chain, clean)
			end
		end
	else
		warn("[TaskService] TaskConfig.StarterChain 缺失或非数组")
	end

	if #chain == 0 then
		warn("[TaskService] 起始任务链为空，使用内置兜底任务")
		table.insert(chain, sanitizeDef(FALLBACK_TASK))
	end
	return chain
end

local CHAIN = buildChain()

-- 解析"可重复 fallback"在链中的下标；找不到则循环链中最后一个任务。
local function resolveFallbackIndex()
	local id = TaskConfig and TaskConfig.RepeatableFallbackId
	if type(id) == "string" then
		for i, def in ipairs(CHAIN) do
			if def.id == id then
				return i
			end
		end
		warn(string.format("[TaskService] RepeatableFallbackId '%s' 不在链中，改为循环最后一个任务", id))
	end
	return #CHAIN
end

local FALLBACK_INDEX = resolveFallbackIndex()

-- ---------- 运行时状态 ----------
-- [player] = { chainIndex = number, def = sanitizedDef, progress = number }
local stateByPlayer = {}

-- 任务 id -> 链下标（用于按 id 恢复存档任务）。
local CHAIN_INDEX_BY_ID = {}
for index, def in ipairs(CHAIN) do
	CHAIN_INDEX_BY_ID[def.id] = index
end

-- 转换为对外的"公开任务数据"（与 MainUI 兼容）。
local function toPublic(state)
	if not state or not state.def then
		return nil
	end
	local def = state.def
	return {
		title = def.title,
		progress = state.progress,
		goal = def.goal,
		rewardCoins = def.rewardCoins,
		rewardXP = def.rewardXP,
	}
end

-- 统一的结果对象。
local function makeResult(progressed, completed, state, reward, reason)
	return {
		progressed = progressed,
		completed = completed,
		task = toPublic(state),
		reward = reward,
		reason = reason,
	}
end

-- 把当前任务状态（仅标识/进度/下标，不含完整定义）写回 PlayerDataService，供持久化。
local function syncToData(player)
	local state = stateByPlayer[player]
	if not state or not state.def then
		return
	end
	PlayerDataService.SetTaskState(player, {
		currentTaskId = state.def.id,
		currentTaskProgress = state.progress,
		taskChainIndex = state.chainIndex,
	})
end

-- 设置玩家当前任务为链上某下标，并指定起始进度。
-- 进度会 clamp 到 0..goal-1，因此恢复存档时不会"一进游戏就自动完成"。同时写回 PlayerDataService。
local function setState(player, index, progress)
	local def = CHAIN[index]
	if not def then
		-- 兜底：不应发生，但保证不崩
		index = #CHAIN
		def = CHAIN[index]
	end
	local clamped = math.clamp(math.floor(progress or 0), 0, math.max(def.goal - 1, 0))
	stateByPlayer[player] = { chainIndex = index, def = def, progress = clamped }
	syncToData(player)
	return stateByPlayer[player]
end

-- 推进到链的下一个任务；链结束则循环可重复 fallback。
local function advanceTask(player)
	local state = stateByPlayer[player]
	local nextIndex = (state and state.chainIndex or 0) + 1
	if CHAIN[nextIndex] then
		return setState(player, nextIndex, 0)
	end
	return setState(player, FALLBACK_INDEX, 0)
end

-- 结算当前任务：发奖励、记录完成、推进到下一个任务。返回完成结果。
local function completeTask(player)
	local state = stateByPlayer[player]
	if not state or not state.def then
		return makeResult(false, false, nil, nil, "no_task")
	end

	local finishedDef = state.def

	-- 1) 发奖励
	local reward = RewardService.GiveReward(player, finishedDef)

	-- 2) 记录完成次数
	local data = PlayerDataService.GetData(player)
	if data then
		data.CompletedTasks[finishedDef.id] = (data.CompletedTasks[finishedDef.id] or 0) + 1
	end

	-- 3) 推进任务（链结束则循环 fallback）
	local nextState = advanceTask(player)

	local result = makeResult(true, true, nextState, reward, "completed")
	result.completedTaskId = finishedDef.id
	return result
end

-- ---------- 公开 API ----------

-- 给玩家分配链上的第一个任务（也用于初始化）。
function TaskService.AssignStarterTask(player)
	local state = setState(player, 1, 0)
	return toPublic(state)
end

-- 从持久化的任务状态恢复；无/过时则安全回退。解析后写回 canonical 状态。
function TaskService.RestoreOrAssign(player)
	local saved = PlayerDataService.GetTaskState(player)

	-- 无存档任务（新玩家）→ 起始任务
	if not saved or type(saved.currentTaskId) ~= "string" then
		return toPublic(setState(player, 1, 0))
	end

	-- task id 仍存在于配置 → 按 id 恢复（进度 clamp 到 0..goal-1）
	local indexById = CHAIN_INDEX_BY_ID[saved.currentTaskId]
	if indexById then
		return toPublic(setState(player, indexById, saved.currentTaskProgress or 0))
	end

	-- task id 过时（配置变更/删除）→ 尝试用 taskChainIndex（进度重置为 0）
	warn(string.format("[TaskService] 存档任务 id '%s' 已不在配置中", tostring(saved.currentTaskId)))
	local ci = saved.taskChainIndex
	if type(ci) == "number" and ci >= 1 and ci <= #CHAIN then
		warn(string.format("[TaskService] 回退到 taskChainIndex=%d（进度重置为 0）", ci))
		return toPublic(setState(player, ci, 0))
	end

	-- 都无效 → 起始任务
	warn("[TaskService] taskChainIndex 也无效，重置为起始任务")
	return toPublic(setState(player, 1, 0))
end

-- 返回玩家当前任务的"公开数据"（与 MainUI 兼容；可能为 nil）。
function TaskService.GetCurrentTask(player)
	return toPublic(stateByPlayer[player])
end

-- 通用加进度。返回一致结果对象 { progressed, completed, task, reward, reason }。
function TaskService.AddProgress(player, amount)
	local state = stateByPlayer[player]
	if not state or not state.def then
		return makeResult(false, false, nil, nil, "no_task")
	end

	amount = (type(amount) == "number" and amount > 0) and amount or 1
	state.progress = math.min(state.def.goal, state.progress + amount)

	if state.progress >= state.def.goal then
		return completeTask(player)
	end

	syncToData(player) -- 写回最新进度，供持久化
	return makeResult(true, false, state, nil, "progressed")
end

-- 事件匹配入口：处理"敌人被击败"事件。
-- 仅当当前任务 type == "DefeatEnemy" 且 target == enemyId 时才加进度。
-- 不匹配则返回非进度结果（不发奖励）。
function TaskService.HandleEnemyDefeated(player, enemyId)
	local state = stateByPlayer[player]
	if not state or not state.def then
		return makeResult(false, false, nil, nil, "no_task")
	end

	local def = state.def
	if def.type ~= "DefeatEnemy" then
		return makeResult(false, false, state, nil, "type_mismatch")
	end
	if def.target ~= enemyId then
		return makeResult(false, false, state, nil, "target_mismatch")
	end

	return TaskService.AddProgress(player, 1)
end

-- 在 PlayerRemoving 时调用：清理内存。
function TaskService.ClearTask(player)
	stateByPlayer[player] = nil
end

return TaskService
