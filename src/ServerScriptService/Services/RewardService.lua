-- RewardService (ModuleScript)
-- 放在 ServerScriptService > Services > RewardService
-- 奖励服务：通过 PlayerDataService 发放金币与经验，并返回结构化结果。
-- 依赖：PlayerDataService。

local PlayerDataService = require(script.Parent.PlayerDataService)

local RewardService = {}

-- 根据"奖励定义"发放金币与经验（任务完成 / 敌人击杀共用此路径）。
-- task 需包含 rewardCoins / rewardXP 字段。
-- XP 升级与技能点累计在 PlayerDataService.AddXP（服务端）内完成；本服务只发奖励并汇总结果。
-- 返回奖励结果对象（旧字段保持不变，Phase 15 追加进度字段）：
-- {
--   coinsAdded = number, xpAdded = number,
--   newCoins   = number, newXP   = number, level = number,
--   skillPoints = number, skillPointsAdded = number, leveledUp = boolean,  -- Phase 15
-- }
function RewardService.GiveReward(player, task)
	local coins = (task and task.rewardCoins) or 0
	local xp = (task and task.rewardXP) or 0

	PlayerDataService.AddCoins(player, coins)
	local _, levelsGained = PlayerDataService.AddXP(player, xp)
	levelsGained = levelsGained or 0

	local data = PlayerDataService.GetData(player)

	return {
		coinsAdded = coins,
		xpAdded = xp,
		newCoins = data and data.Coins or 0,
		newXP = data and data.XP or 0,
		level = data and data.Level or 1,
		-- Phase 15：进度反馈（向后兼容）。
		skillPoints = data and data.SkillPoints or 0,
		skillPointsAdded = levelsGained, -- 本次奖励的升级数 = 新增技能点数
		leveledUp = levelsGained > 0,
	}
end

return RewardService
