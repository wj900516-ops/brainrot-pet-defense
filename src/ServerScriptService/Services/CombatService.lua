-- CombatService (ModuleScript)
-- 放在 ServerScriptService > Services > CombatService
-- Phase 8：宠物 → 敌人 的服务端自动战斗。
--
-- 职责（纯机制，server-authoritative）：
--   * 每帧为每位"拥有已装备宠物"的玩家，寻找其宠物范围内最近的存活敌人。
--   * 按宠物攻击间隔对该敌人造成伤害（EnemyService.DamageEnemy）。
--   * 若这一击击杀，则通过 onEnemyKilled(ownerPlayer, enemy) 通知（由 ServerInit 决定奖励）。
--
-- 边界：
--   * 不发奖励、不写 DataStore、不改宠物数据 —— 只做"伤害判定"。
--   * 不信任客户端：是否攻击/打谁/打多少全部由服务端决定。
--   * 只读 PetService.GetActivePet（宠物位置/属性）与 EnemyService（敌人列表），不修改其内部状态。
--   * 复用 Phase 5/7 的"已装备宠物"概念：未装备 → 无 active pet → 不攻击敌人。

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PetService = require(script.Parent.PetService)
local EnemyService = require(script.Parent.EnemyService)
local SkillEffectResolver = require(script.Parent.SkillEffectResolver) -- Phase 16B：pet_damage 修正

local CombatService = {}

-- ---------- 默认战斗参数（宠物 def 缺字段时兜底） ----------
local DEFAULT_RANGE = 18
local DEFAULT_DAMAGE = 12
local DEFAULT_INTERVAL = 2.25

local started = false
local onEnemyKilled = nil
local combatCooldown = {} -- [player] = os.clock()，CombatService 自有冷却，不污染 PetService 记录

-- 寻找宠物范围内最近的存活敌人。
local function findNearestEnemy(petPosition, range)
	local nearest, nearestDist
	for _, enemy in ipairs(EnemyService.GetAliveEnemies()) do
		if enemy.model and enemy.model.Parent then
			local dist = (enemy.model.Position - petPosition).Magnitude
			if dist <= range and (not nearestDist or dist < nearestDist) then
				nearest = enemy
				nearestDist = dist
			end
		end
	end
	return nearest
end

-- 启动战斗循环（幂等）。options.onEnemyKilled(player, enemy) 可选。
function CombatService.Start(options)
	if started then
		return
	end
	started = true
	onEnemyKilled = options and options.onEnemyKilled

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local pet = PetService.GetActivePet(player) -- { model, def } 或 nil（未装备则 nil）
			if pet and pet.model and pet.model.Parent and pet.def then
				local range = (type(pet.def.attackRange) == "number") and pet.def.attackRange or DEFAULT_RANGE
				local damage = (type(pet.def.attackDamage) == "number") and pet.def.attackDamage or DEFAULT_DAMAGE
				local interval = (type(pet.def.attackInterval) == "number") and pet.def.attackInterval or DEFAULT_INTERVAL

				if (now - (combatCooldown[player] or 0)) >= interval then
					local target = findNearestEnemy(pet.model.Position, range)
					if target then
						combatCooldown[player] = now
						-- Phase 16B：应用宠物主人的 pet_damage 修正（PetDamageMultiplier，O(1) 读缓存；
						-- 客户端无法影响）。宠物基础伤害仍来自服务端 PetConfig。
						local petBonus = SkillEffectResolver.GetNumber(player, "PetDamageMultiplier", 0)
						-- 用浮点精确施加 +%（敌人 hp 为浮点，DamageEnemy 接受浮点），避免对小整数取整抹掉低级加成。
						local effDamage = damage * (1 + math.max(0, petBonus))
						local killed = EnemyService.DamageEnemy(target, effDamage)
						if killed and onEnemyKilled then
							onEnemyKilled(player, target)
						end
					end
				end
			end
		end
	end)

	-- 玩家离开时清理其战斗冷却记录。
	Players.PlayerRemoving:Connect(function(player)
		combatCooldown[player] = nil
	end)
end

return CombatService
