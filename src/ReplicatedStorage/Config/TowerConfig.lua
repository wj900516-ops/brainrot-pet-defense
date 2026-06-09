-- TowerConfig (ModuleScript)
-- 放在 ReplicatedStorage > Config > TowerConfig
-- Phase 11：基础塔配置（仅放置所需）。占位视觉，无美术依赖。
-- range/damage/attackInterval 为 Phase 12 塔攻击参数（自动攻击范围内最近敌人）。

local TowerConfig = {}

TowerConfig.BasicTowerId = "basic_tower"

TowerConfig.Towers = {
	basic_tower = {
		id = "basic_tower",
		displayName = "Tower",
		cost = 100, -- 固定花费（金币）
		-- 占位视觉
		size = Vector3.new(4, 8, 4),
		color = Color3.fromRGB(120, 130, 245),
		-- Phase 12 战斗参数
		range = 24, -- 攻击范围（studs，水平）
		damage = 8, -- 每次攻击伤害
		attackInterval = 1.0, -- 两次攻击的间隔（秒）
	},
}

-- 返回基础塔定义（找不到返回 nil，由 TowerService 兜底）。
function TowerConfig.GetBasicTower()
	return TowerConfig.Towers[TowerConfig.BasicTowerId]
end

return TowerConfig
