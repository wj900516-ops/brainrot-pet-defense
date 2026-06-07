-- EnemyConfig: 敌人配置表
-- 放在 ReplicatedStorage > Config > EnemyConfig (ModuleScript)

local EnemyConfig = {
	LagBlob = {
		displayName  = "Lag Blob",
		health       = 24,       -- 血量（Phase 8 调平：50→24，保证宠物能在逃逸前击杀）
		speed        = 4,        -- 移动速度 studs/秒（Phase 8 调平：8→4，给宠物足够输出时间）
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
