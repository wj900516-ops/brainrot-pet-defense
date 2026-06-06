-- GameManager (Script)
-- 放在 ServerScriptService > GameManager
-- 主控脚本：管理游戏状态、初始化、胜负判定

--[[ Day 2 TODO:
	1. 游戏开始时初始化金币和基地血量
	2. 监听基地血量变化，血量 <= 0 时游戏失败
	3. 所有波次结束且基地存活 → 游戏胜利
	4. 通知客户端更新 UI
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WaveConfig = require(ReplicatedStorage.Config.WaveConfig)

-- 游戏状态
local gameState = {
	coins     = WaveConfig.startingCoins,
	baseHp    = WaveConfig.baseHealth,
	maxBaseHp = WaveConfig.baseHealth,
	wave      = 0,
	maxWaves  = #WaveConfig.waves,
	running   = false,
}

print("[GameManager] Loaded. Waiting for Day 2 logic...")
