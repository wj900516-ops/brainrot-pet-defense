-- WaveManager (ModuleScript)
-- 放在 ServerScriptService > WaveManager
-- 波次管理：按 WaveConfig 刷怪，控制波次间隔

--[[ Day 2 TODO:
	1. startWave(waveNumber) - 按配置刷怪
	2. 每刷一只怪调用 EnemyService.spawnEnemy()
	3. 一波刷完后等待所有怪被消灭或到达基地
	4. 波间暂停后自动开始下一波
]]

local WaveManager = {}

print("[WaveManager] Loaded. Waiting for Day 2 logic...")

return WaveManager
