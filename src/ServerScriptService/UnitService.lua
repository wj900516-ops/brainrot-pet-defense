-- UnitService (ModuleScript)
-- 放在 ServerScriptService > UnitService
-- 塔/宠物管理：放置、攻击、升级

--[[ Day 2-3 TODO:
	1. placeUnit(player, unitId, spot) - 在塔位放塔，扣金币
	2. startAttackLoop(unit) - 塔自动检测范围内敌人并攻击
	3. findTarget(unit) - 找最近的/最前面的敌人
	4. dealDamage(unit, enemy) - 调用 EnemyService.takeDamage
]]

local UnitService = {}

print("[UnitService] Loaded. Waiting for Day 2-3 logic...")

return UnitService
