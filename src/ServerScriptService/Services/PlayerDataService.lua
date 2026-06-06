-- PlayerDataService (ModuleScript)
-- 放在 ServerScriptService > Services > PlayerDataService
-- 玩家数据服务：负责初始化 / 读取 / 修改 / 持久化玩家数据。
--
-- Phase 4：接入 Roblox DataStoreService（安全封装）。
--   * 本模块"拥有"持久化玩家状态；TaskService 通过 GetTaskState/SetTaskState 读写任务状态。
--   * 仅持久化标识/状态，不存储 TaskConfig 的完整任务定义。
--   * pcall 包裹 GetDataStore/GetAsync/SetAsync；有限重试；失败回退默认值；绝不崩服、绝不无限 yield。
--   * 加载失败的会话标记为"不可保存"，离开时跳过保存，避免覆盖云端好数据。
-- 本模块不依赖其他游戏 Service（最底层），不感知 Remote。

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerDataService = {}

-- ---------- 常量 ----------
local CURRENT_DATA_VERSION = 1
local DATASTORE_NAME = "PlayerData_v1"
local MAX_RETRIES = 3
local RETRY_DELAY = 2 -- 秒
local XP_PER_LEVEL = 100 -- 每级所需经验（XP 表示当前等级内进度 0 ~ XP_PER_LEVEL-1）
local AUTO_SAVE_INTERVAL_SECONDS = 180 -- 周期自动保存间隔（安全网）
local AUTO_SAVE_STAGGER_SECONDS = 0.1 -- 同批玩家之间的轻微错峰，避免同帧批量 SetAsync

-- ---------- 运行时状态 ----------
local dataByPlayer = {} -- [player] = dataTable
local saveBlocked = {} -- [player] = true 表示该会话不可保存（加载失败/无持久化）

-- ---------- 工具 ----------

-- 深拷贝（仅含基础类型与表，保证可序列化、无共享引用）。
local function deepCopy(source)
	local out = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			out[key] = deepCopy(value)
		else
			out[key] = value
		end
	end
	return out
end

-- 默认数据（每次调用都生成全新的表，玩家之间互不共享引用）。
local function defaultData()
	return {
		DataVersion = CURRENT_DATA_VERSION,
		Coins = 0,
		Level = 1,
		XP = 0,
		CompletedTasks = {}, -- [taskId] = 完成次数
		Inventory = {},
		Settings = {},
		Task = {
			currentTaskId = nil, -- 新玩家无任务 id，由 TaskService 分配起始任务后写回
			currentTaskProgress = 0,
			taskChainIndex = 1,
		},
	}
end

-- 把"读到的存档"合并进一份全新默认数据（缺字段补默认、坏字段忽略并告警）。
-- 这同时充当 v1 的迁移逻辑：未来版本可在此按 DataVersion 分支处理。
local function reconcile(loaded)
	local data = defaultData()
	if type(loaded) ~= "table" then
		warn("[PlayerDataService] 存档不是表，使用默认数据")
		return data
	end

	local version = type(loaded.DataVersion) == "number" and loaded.DataVersion or 0
	if version ~= CURRENT_DATA_VERSION then
		warn(string.format(
			"[PlayerDataService] 存档版本 %s != 当前 %d，按当前结构补齐/迁移",
			tostring(version),
			CURRENT_DATA_VERSION
		))
		-- 目前仅 v1：reconcile 本身即迁移。未来新增版本时在此分支处理字段变化。
	end

	if type(loaded.Coins) == "number" then
		data.Coins = loaded.Coins
	end
	if type(loaded.Level) == "number" then
		data.Level = math.max(1, math.floor(loaded.Level))
	end
	if type(loaded.XP) == "number" then
		data.XP = math.max(0, math.floor(loaded.XP))
	end

	if type(loaded.CompletedTasks) == "table" then
		for taskId, count in pairs(loaded.CompletedTasks) do
			if type(taskId) == "string" and type(count) == "number" then
				data.CompletedTasks[taskId] = count
			end
		end
	end

	if type(loaded.Inventory) == "table" then
		data.Inventory = deepCopy(loaded.Inventory)
	end
	if type(loaded.Settings) == "table" then
		data.Settings = deepCopy(loaded.Settings)
	end

	if type(loaded.Task) == "table" then
		local t = loaded.Task
		if type(t.currentTaskId) == "string" then
			data.Task.currentTaskId = t.currentTaskId
		end
		if type(t.currentTaskProgress) == "number" then
			data.Task.currentTaskProgress = math.max(0, math.floor(t.currentTaskProgress))
		end
		if type(t.taskChainIndex) == "number" then
			data.Task.taskChainIndex = math.max(1, math.floor(t.taskChainIndex))
		end
	end

	data.DataVersion = CURRENT_DATA_VERSION
	return data
end

-- 有限重试地执行一个可能失败/yield 的函数。返回 (ok, resultOrError)。
local function withRetry(fn)
	local lastErr
	for attempt = 1, MAX_RETRIES do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end
	return false, lastErr
end

local function keyFor(player)
	return "Player_" .. tostring(player.UserId)
end

-- ---------- DataStore 句柄（启动时获取一次，失败则进入无持久化模式） ----------
local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		store = nil
		warn("[PlayerDataService] GetDataStore 失败（可能未开启 API Services）：" .. tostring(result)
			.. " —— 进入无持久化模式")
	end
end

-- ---------- 加载 / 保存 ----------

-- 在 PlayerAdded 时调用：加载（或返回已加载的）玩家数据。会 yield。
-- 任何失败都回退默认数据，并把会话标记为不可保存，保证可玩、不崩服、不覆盖云端。
function PlayerDataService.LoadData(player)
	if dataByPlayer[player] then
		return dataByPlayer[player]
	end

	local data

	if not store then
		warn(string.format(
			"[PlayerDataService] 无 DataStore（API 未开启？），玩家 %s 使用默认数据，本次会话不保存",
			player.Name
		))
		data = defaultData()
		saveBlocked[player] = true
	else
		local ok, loaded = withRetry(function()
			return store:GetAsync(keyFor(player))
		end)

		if not ok then
			warn(string.format(
				"[PlayerDataService] 读取玩家 %s 存档失败：%s —— 使用默认数据并跳过保存以免覆盖云端",
				player.Name,
				tostring(loaded)
			))
			data = defaultData()
			saveBlocked[player] = true
		elseif loaded == nil then
			-- 新玩家
			data = defaultData()
			saveBlocked[player] = false
		else
			data = reconcile(loaded)
			saveBlocked[player] = false
		end
	end

	dataByPlayer[player] = data
	return data
end

-- 在 PlayerRemoving / BindToClose 时调用：保存玩家数据。会 yield。
-- 返回是否成功保存。失败仅告警，绝不崩服。加载失败的会话会被跳过。
function PlayerDataService.SaveData(player)
	local data = dataByPlayer[player]
	if not data then
		return false
	end

	if saveBlocked[player] then
		warn(string.format(
			"[PlayerDataService] 玩家 %s 会话标记为不可保存（加载失败/无持久化），跳过保存",
			player.Name
		))
		return false
	end

	if not store then
		return false
	end

	local ok, err = withRetry(function()
		return store:SetAsync(keyFor(player), data)
	end)

	if not ok then
		warn(string.format("[PlayerDataService] 保存玩家 %s 失败：%s", player.Name, tostring(err)))
		return false
	end

	return true
end

-- ---------- 读取 / 修改（内存） ----------

-- 返回完整的服务端数据表（可直接读写，调用方需自负其责）。
function PlayerDataService.GetData(player)
	return dataByPlayer[player]
end

-- 增加金币，返回更新后的数据表。
function PlayerDataService.AddCoins(player, amount)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	data.Coins += amount
	return data
end

-- 增加经验并处理升级，返回更新后的数据表。
function PlayerDataService.AddXP(player, amount)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	data.XP += amount
	while data.XP >= XP_PER_LEVEL do
		data.XP -= XP_PER_LEVEL
		data.Level += 1
	end
	return data
end

-- 返回可安全发送给客户端的精简数据（不含 Inventory/Settings 等字段）。
function PlayerDataService.GetPublicData(player)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	return {
		Coins = data.Coins,
		Level = data.Level,
		XP = data.XP,
		XpForNextLevel = XP_PER_LEVEL,
	}
end

-- ---------- 任务状态的干净读写 API（供 TaskService 使用） ----------

-- 返回当前持久化的任务状态拷贝（避免外部直接改内部表）。
function PlayerDataService.GetTaskState(player)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	return {
		currentTaskId = data.Task.currentTaskId,
		currentTaskProgress = data.Task.currentTaskProgress,
		taskChainIndex = data.Task.taskChainIndex,
	}
end

-- 写入任务状态（仅标识/进度/下标，不含完整任务定义）。
function PlayerDataService.SetTaskState(player, taskState)
	local data = dataByPlayer[player]
	if not data or type(taskState) ~= "table" then
		return
	end
	data.Task.currentTaskId = taskState.currentTaskId
	data.Task.currentTaskProgress = taskState.currentTaskProgress or 0
	data.Task.taskChainIndex = taskState.taskChainIndex or 1
end

-- 在保存之后调用：清理内存数据与会话标记。
function PlayerDataService.ClearData(player)
	dataByPlayer[player] = nil
	saveBlocked[player] = nil
end

-- ---------- 周期自动保存（安全网） ----------
-- 由 ServerInit 在启动时调用一次（幂等）。这是对 PlayerRemoving / BindToClose 保存的补充，
-- 不是替代：用于降低服务器崩溃 / 异常关闭导致的进度丢失窗口。
local autoSaveStarted = false
function PlayerDataService.StartAutoSave()
	if autoSaveStarted then
		return
	end
	autoSaveStarted = true

	task.spawn(function()
		while true do
			-- 先等待一个完整间隔，避免上线即批量保存；也保证循环绝不会变成紧密空转。
			task.wait(AUTO_SAVE_INTERVAL_SECONDS)

			for _, player in ipairs(Players:GetPlayers()) do
				if dataByPlayer[player] then
					-- SaveData 内部已 pcall 且尊重 saveBlocked（加载失败的会话会被跳过，
					-- 因此自动保存不会用默认数据覆盖云端好数据）；外层再 pcall 双保险，
					-- 确保任一玩家保存失败/抛错都不会中断整个自动保存循环。
					local ok, err = pcall(PlayerDataService.SaveData, player)
					if not ok then
						warn("[PlayerDataService] 自动保存玩家 " .. player.Name .. " 时异常：" .. tostring(err))
					end
					-- 轻微错峰，避免同一帧内对多名玩家批量 SetAsync。
					task.wait(AUTO_SAVE_STAGGER_SECONDS)
				end
			end
		end
	end)
end

return PlayerDataService
