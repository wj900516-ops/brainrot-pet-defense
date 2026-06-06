-- PlayerDataService (ModuleScript)
-- 放在 ServerScriptService > Services > PlayerDataService
-- 玩家数据服务：负责初始化 / 读取 / 修改玩家数据。
--
-- 当前阶段：仅内存存储（in-memory）。
-- 结构已为将来接入 DataStore 持久化预留（见 InitData / ClearData 注释）。
-- 本模块不依赖任何其他服务（最底层），不感知 Remote。

local PlayerDataService = {}

-- 每升一级所需经验。XP 表示"当前等级内的进度"(0 ~ XP_PER_LEVEL-1)。
local XP_PER_LEVEL = 100

-- [player] = dataTable
local dataByPlayer = {}

-- 默认初始数据结构（每位玩家一份独立副本）
local function defaultData()
	return {
		Coins = 0,
		Level = 1,
		XP = 0,
		CompletedTasks = {}, -- [taskId] = 完成次数
		Inventory = {},
		Settings = {},
	}
end

-- 在 PlayerAdded 时调用：初始化（或返回已存在的）玩家数据。
function PlayerDataService.InitData(player)
	if dataByPlayer[player] then
		return dataByPlayer[player]
	end

	-- 将来接入 DataStore：在此处读取存档并合并进 defaultData()。
	local data = defaultData()
	dataByPlayer[player] = data
	return data
end

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

-- 返回可安全发送给客户端的精简数据（不含 Inventory/Settings 等敏感字段）。
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

-- 在 PlayerRemoving 时调用：清理内存数据。
function PlayerDataService.ClearData(player)
	-- 将来接入 DataStore：在此处把 dataByPlayer[player] 保存回存档。
	dataByPlayer[player] = nil
end

return PlayerDataService
