-- WaveService (ModuleScript)
-- 放在 ServerScriptService > Services > WaveService
-- Phase 8：极简刷怪节奏 —— 每隔固定间隔生成一个敌人，受同时存活上限约束。
-- 不做复杂波次/Boss/难度曲线（留待后续阶段）。
--
-- 边界：只负责"何时生成"，把"生成什么/怎么动"交给 EnemyService。

local EnemyService = require(script.Parent.EnemyService)

local WaveService = {}

-- ---------- 可调参数 ----------
local SPAWN_INTERVAL_SECONDS = 4 -- 两次生成的间隔
local MAX_ALIVE_ENEMIES = 8 -- 同时存活上限（避免无限堆积）
local ENEMY_ID = "LagBlob" -- 本阶段只刷一种敌人

local started = false

-- 启动刷怪循环（幂等）。后台 task.spawn，先等待再生成，绝不紧密空转。
function WaveService.Start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL_SECONDS)
			if #EnemyService.GetAliveEnemies() < MAX_ALIVE_ENEMIES then
				EnemyService.SpawnEnemy(ENEMY_ID)
			end
		end
	end)
end

return WaveService
