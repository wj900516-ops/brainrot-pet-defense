-- TaskService (ModuleScript)
-- 放在 ServerScriptService > Services > TaskService
-- 任务服务：分配 / 跟踪 / 完成玩家任务。
-- 依赖：RewardService、PlayerDataService。
-- 不感知 Remote —— 由 ServerInit 负责把结果推送给客户端。

local PlayerDataService = require(script.Parent.PlayerDataService)
local RewardService = require(script.Parent.RewardService)

local TaskService = {}

-- 起始任务定义（MVP 阶段唯一任务，完成后会重置/重复）。
local STARTER_TASK = {
	id = "starter_collect",
	title = "Complete your first action",
	goal = 1,
	rewardCoins = 50,
	rewardXP = 25,
}

-- [player] = 当前任务实例 { id, title, goal, progress, rewardCoins, rewardXP }
local taskByPlayer = {}

-- 由任务定义生成一份带进度的任务实例
local function makeTask(def)
	return {
		id = def.id,
		title = def.title,
		goal = def.goal,
		progress = 0,
		rewardCoins = def.rewardCoins,
		rewardXP = def.rewardXP,
	}
end

-- 给玩家分配起始任务（也用于完成后重置）。
function TaskService.AssignStarterTask(player)
	taskByPlayer[player] = makeTask(STARTER_TASK)
	return taskByPlayer[player]
end

-- 返回玩家当前任务（可能为 nil）。
function TaskService.GetCurrentTask(player)
	return taskByPlayer[player]
end

-- 增加任务进度。达到目标时自动结算并分配下一个任务。
-- 返回结果对象：
-- { task = 当前任务, completed = bool, reward = 奖励结果或nil, completedTaskId = string或nil }
function TaskService.AddProgress(player, amount)
	local current = taskByPlayer[player]
	if not current then
		return nil
	end

	amount = amount or 1
	current.progress = math.min(current.goal, current.progress + amount)

	if current.progress >= current.goal then
		return TaskService.CompleteTask(player)
	end

	return { task = current, completed = false, reward = nil, completedTaskId = nil }
end

-- 结算当前任务：发奖励、记录完成、分配下一个（可重复）任务。
function TaskService.CompleteTask(player)
	local finished = taskByPlayer[player]
	if not finished then
		return nil
	end

	-- 1) 发放奖励
	local reward = RewardService.GiveReward(player, finished)

	-- 2) 在玩家数据中记录完成次数
	local data = PlayerDataService.GetData(player)
	if data then
		data.CompletedTasks[finished.id] = (data.CompletedTasks[finished.id] or 0) + 1
	end

	-- 3) MVP：重置同一个起始任务，使核心循环可重复
	local nextTask = TaskService.AssignStarterTask(player)

	return {
		task = nextTask,
		completed = true,
		reward = reward,
		completedTaskId = finished.id,
	}
end

-- 在 PlayerRemoving 时调用：清理内存。
function TaskService.ClearTask(player)
	taskByPlayer[player] = nil
end

return TaskService
