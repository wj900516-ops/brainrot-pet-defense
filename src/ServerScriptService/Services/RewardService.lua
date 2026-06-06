-- RewardService (ModuleScript)
-- 放在 ServerScriptService > Services > RewardService
-- 奖励服务：通过 PlayerDataService 发放金币与经验，并返回结构化结果。
-- 依赖：PlayerDataService。

local PlayerDataService = require(script.Parent.PlayerDataService)

local RewardService = {}

-- 根据任务定义发放奖励。
-- task 需包含 rewardCoins / rewardXP 字段。
-- 返回奖励结果对象：
-- {
--   coinsAdded = number,
--   xpAdded    = number,
--   newCoins   = number,
--   newXP      = number,
--   level      = number,
-- }
function RewardService.GiveReward(player, task)
	local coins = (task and task.rewardCoins) or 0
	local xp = (task and task.rewardXP) or 0

	PlayerDataService.AddCoins(player, coins)
	PlayerDataService.AddXP(player, xp)

	local data = PlayerDataService.GetData(player)

	return {
		coinsAdded = coins,
		xpAdded = xp,
		newCoins = data and data.Coins or 0,
		newXP = data and data.XP or 0,
		level = data and data.Level or 1,
	}
end

return RewardService
