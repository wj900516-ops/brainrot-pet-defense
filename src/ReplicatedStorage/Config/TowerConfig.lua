-- TowerConfig (ModuleScript)
-- 放在 ReplicatedStorage > Config > TowerConfig
-- Phase 11：基础塔配置（仅放置所需）。占位视觉，无美术依赖。
-- range/damage/fireInterval 为 Phase 12 战斗预留的 stub，本阶段不使用。

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
		-- Phase 12 战斗 stub（本阶段不读取）
		range = 24,
		damage = 8,
		fireInterval = 1.0,
	},
}

-- 返回基础塔定义（找不到返回 nil，由 TowerService 兜底）。
function TowerConfig.GetBasicTower()
	return TowerConfig.Towers[TowerConfig.BasicTowerId]
end

return TowerConfig
