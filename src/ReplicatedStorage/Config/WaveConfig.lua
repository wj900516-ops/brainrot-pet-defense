-- WaveConfig: 波次配置表
-- 放在 ReplicatedStorage > Config > WaveConfig (ModuleScript)

local WaveConfig = {
	startingCoins = 200,    -- 玩家初始金币
	baseHealth    = 20,     -- 基地初始血量
	wavePause     = 5,      -- 波与波之间的间隔（秒）

	waves = {
		-- Wave 1: 5 个 Lag Blob
		{
			enemies = {
				{ enemyId = "LagBlob", count = 5, spawnInterval = 1.5 },
			},
		},

		-- Wave 2: 8 个 Lag Blob，刷得更快
		{
			enemies = {
				{ enemyId = "LagBlob", count = 8, spawnInterval = 1.2 },
			},
		},

		-- Wave 3: 5 个 Lag Blob + 1 个 Boss
		{
			enemies = {
				{ enemyId = "LagBlob",         count = 5, spawnInterval = 1.0 },
				{ enemyId = "StinkyBreadBoss",  count = 1, spawnInterval = 0   },
			},
		},
	},
}

return WaveConfig
