-- EnemyConfig: 敌人配置表
-- 放在 ReplicatedStorage > Config > EnemyConfig (ModuleScript)

local EnemyConfig = {
	LagBlob = {
		displayName  = "Lag Blob",
		health       = 50,       -- 血量
		speed        = 8,        -- 移动速度 (studs/秒)
		baseDamage   = 1,        -- 到达基地时造成的伤害
		killReward   = 15,       -- 击杀奖励金币
		-- 以后扩展:
		-- model     = "LagBlob",
		-- isBoss    = false,
	},

	StinkyBreadBoss = {
		displayName  = "Stinky Bread Boss",
		health       = 300,
		speed        = 5,
		baseDamage   = 5,
		killReward   = 50,
		-- isBoss    = true,
	},
}

return EnemyConfig
