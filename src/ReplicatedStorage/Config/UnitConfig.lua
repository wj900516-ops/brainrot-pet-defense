-- UnitConfig: 塔/宠物配置表
-- 放在 ReplicatedStorage > Config > UnitConfig (ModuleScript)

local UnitConfig = {
	ToastDog = {
		displayName = "Toast Dog",
		price       = 100,       -- 放置价格
		damage      = 10,        -- 每次攻击伤害
		fireRate    = 1,         -- 攻击间隔（秒）
		range       = 15,        -- 攻击范围（studs）
		-- 以后扩展:
		-- model    = "ToastDog", -- ReplicatedStorage.Units 里的模型名
		-- rarity   = "Common",
		-- level    = 1,
	},
}

return UnitConfig
