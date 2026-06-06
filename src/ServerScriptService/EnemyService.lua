-- EnemyService (ModuleScript)
-- 放在 ServerScriptService > EnemyService
-- 敌人管理：生成、移动、受伤、死亡、到达基地

--[[ Day 2 TODO:
	1. spawnEnemy(enemyId) - 在 SpawnPoint 生成敌人
	2. moveAlongPath(enemy) - 沿 Node1→Node6 移动
	3. takeDamage(enemy, dmg) - 扣血，血量<=0 时死亡
	4. onReachBase(enemy) - 到达基地，扣基地血量，消灭自己
	5. onDeath(enemy) - 给玩家加金币
]]

local EnemyService = {}

-- 获取路径点（按名字排序）
local function getPathNodes()
	local pathNodes = game.Workspace:FindFirstChild("PathNodes")
	if not pathNodes then return {} end

	local nodes = {}
	for _, node in ipairs(pathNodes:GetChildren()) do
		table.insert(nodes, node)
	end
	table.sort(nodes, function(a, b)
		return a.Name < b.Name
	end)
	return nodes
end

print("[EnemyService] Loaded. Path nodes found: " .. #getPathNodes())

return EnemyService
