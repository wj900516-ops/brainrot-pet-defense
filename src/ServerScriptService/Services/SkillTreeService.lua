-- SkillTreeService (ModuleScript)
-- 放在 ServerScriptService > Services > SkillTreeService
-- Phase 16B：玩家技能树的服务端权威逻辑（加载清洗 / 动态算点 / 校验消费 / 应用升级 / 通知 EffectResolver）。
--
-- 设计：
--   * 客户端只发"消费意图"（skillId）；本服务做全部校验与状态变更，绝不信任客户端的 rank/cost/点数。
--   * 派生量（branchPoints / totalPoints）一律从 Unlocked + SkillTreeConfig【动态计算】，不持久化。
--   * Phase 16B 仅开放 3 个技能（allowlist）；其余节点配置可见但不可消费（返回 not_implemented）。
--   * 每玩家消费去抖（0.2s）+ 处理锁，防双击/宏重复消费；点数不会变负、rank 不超 maxRank（每次重新校验保证）。

local PlayerDataService = require(script.Parent.PlayerDataService)
local SkillEffectResolver = require(script.Parent.SkillEffectResolver)

local SkillTreeService = {}

-- ---------- Phase 16B 可消费技能 allowlist（其余仅配置可见、不可消费） ----------
local ENABLED = {
	eco_kill_coins = true,
	twr_damage = true,
	pet_damage = true,
}
-- 稳定顺序（供调试 UI 列表）。
local ENABLED_ORDER = { "eco_kill_coins", "twr_damage", "pet_damage" }

-- ---------- 消费去抖 / 处理锁（每玩家） ----------
local SPEND_DEBOUNCE_SECONDS = 0.2
local lastSpend = {} -- [player] = os.clock()
local spendLock = {} -- [player] = true 处理中

-- ---------- 加载 SkillTreeConfig（容错） ----------
local SkillTreeConfig
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local configFolder = ReplicatedStorage:FindFirstChild("Config")
	local module = configFolder and configFolder:FindFirstChild("SkillTreeConfig")
	if module then
		local ok, result = pcall(require, module)
		if ok and type(result) == "table" then
			SkillTreeConfig = result
		else
			warn("[SkillTreeService] require SkillTreeConfig 失败：" .. tostring(result))
		end
	else
		warn("[SkillTreeService] 未找到 ReplicatedStorage.Config.SkillTreeConfig")
	end
end

local function getNode(skillId)
	if SkillTreeConfig and SkillTreeConfig.GetById then
		return SkillTreeConfig.GetById(skillId)
	end
	return nil
end

-- ---------- 动态算点（不持久化派生量） ----------

-- 全部已投等级之和。
function SkillTreeService.GetTotalPoints(player)
	local total = 0
	for _, rank in pairs(PlayerDataService.GetSkillTreeUnlocked(player)) do
		if type(rank) == "number" then
			total += rank
		end
	end
	return total
end

-- 某分支已投等级之和。
function SkillTreeService.GetBranchPoints(player, branch)
	local sum = 0
	for skillId, rank in pairs(PlayerDataService.GetSkillTreeUnlocked(player)) do
		if type(rank) == "number" then
			local node = getNode(skillId)
			if node and node.branch == branch then
				sum += rank
			end
		end
	end
	return sum
end

-- ---------- 加载清洗（配置感知；PlayerDataService 已做结构性清洗） ----------
-- 丢弃未知 skillId（Phase 16B 无历史技能树数据，简单安全丢弃，不退点 —— 见 docs）。
-- 把 rank 夹到 [0, maxRank]。在玩家加载后、Rebuild 前调用。
function SkillTreeService.SanitizeOnLoad(player)
	local unlocked = PlayerDataService.GetSkillTreeUnlocked(player)
	for skillId, rank in pairs(unlocked) do
		local node = getNode(skillId)
		if not node then
			PlayerDataService.SetSkillRank(player, skillId, 0) -- 丢弃未知（不退点）
			warn(string.format("[SkillTreeService] 丢弃未知技能 '%s'（无对应配置，不退点）", tostring(skillId)))
		else
			local maxRank = (type(node.maxRank) == "number") and node.maxRank or 0
			local clamped = math.clamp(math.floor(rank), 0, maxRank)
			if clamped ~= rank then
				PlayerDataService.SetSkillRank(player, skillId, clamped)
				warn(string.format("[SkillTreeService] 技能 '%s' rank 夹紧 %s -> %d", skillId, tostring(rank), clamped))
			end
		end
	end
end

-- ---------- 消费校验 + 应用（无 yield） ----------
local function doSpend(player, skillId)
	local node = getNode(skillId)
	if not node then
		return { success = false, reason = "unknown_skill", skillId = skillId }
	end
	if not ENABLED[skillId] then
		return { success = false, reason = "not_implemented", skillId = skillId }
	end

	local currentRank = PlayerDataService.GetSkillRank(player, skillId)
	local maxRank = (type(node.maxRank) == "number") and node.maxRank or 0
	if currentRank >= maxRank then
		return { success = false, reason = "max_rank", skillId = skillId, rank = currentRank }
	end

	local cost = (type(node.costPerRank) == "number" and node.costPerRank > 0) and math.floor(node.costPerRank) or nil
	if not cost then
		return { success = false, reason = "bad_cost", skillId = skillId }
	end

	local skillPoints = PlayerDataService.GetSkillPoints(player)
	if skillPoints < cost then
		return { success = false, reason = "not_enough_points", skillId = skillId }
	end

	-- 结构化前置：前置节点等级 / 分支投资 / 总投资。
	local req = node.requirements or {}
	for _, pre in ipairs(req.prerequisiteNodes or {}) do
		if type(pre) == "table" and PlayerDataService.GetSkillRank(player, pre.id) < (pre.rank or 0) then
			return { success = false, reason = "prereq_node", skillId = skillId }
		end
	end
	if SkillTreeService.GetBranchPoints(player, node.branch) < (req.requiredBranchPoints or 0) then
		return { success = false, reason = "prereq_branch", skillId = skillId }
	end
	if SkillTreeService.GetTotalPoints(player) < (req.requiredTotalPoints or 0) then
		return { success = false, reason = "prereq_total", skillId = skillId }
	end

	-- 通过 → 扣点 + 升级 + 重建缓存（顺序：先扣点再写 rank）。
	PlayerDataService.AddSkillPoints(player, -cost)
	local newRank = currentRank + 1
	PlayerDataService.SetSkillRank(player, skillId, newRank)
	SkillEffectResolver.Rebuild(player)

	return {
		success = true,
		reason = "spent",
		skillId = skillId,
		rank = newRank,
		skillPoints = PlayerDataService.GetSkillPoints(player),
	}
end

-- 消费一点到 skillId。客户端只发 skillId；本函数做去抖/锁 + 全部校验。
-- 返回 { success, reason, skillId?, rank?, skillPoints? }。
function SkillTreeService.TrySpend(player, skillId)
	if not player then
		return { success = false, reason = "no_player" }
	end
	if type(skillId) ~= "string" or skillId == "" then
		return { success = false, reason = "bad_request" }
	end

	-- 处理锁（防 doSpend 万一 yield 时的重入；本实现 doSpend 无 yield）。
	if spendLock[player] then
		return { success = false, reason = "busy", skillId = skillId }
	end
	-- 时间去抖：每 0.2s 至多处理一次消费请求（双击/宏不会重复扣点）。
	local now = os.clock()
	local last = lastSpend[player]
	if last and (now - last) < SPEND_DEBOUNCE_SECONDS then
		return { success = false, reason = "too_fast", skillId = skillId }
	end

	spendLock[player] = true
	lastSpend[player] = now
	local ok, result = pcall(doSpend, player, skillId)
	spendLock[player] = nil

	if not ok then
		warn("[SkillTreeService] doSpend 异常：" .. tostring(result))
		return { success = false, reason = "error", skillId = skillId }
	end
	return result
end

-- ---------- 公开状态（供调试 UI） ----------
-- 返回 { skillPoints, totalPoints, unlocked={[id]=rank}, skills=[{id,name,branch,rank,maxRank,cost,description}] }。
-- 仅暴露拷贝/精简信息，不暴露可变内部表。
function SkillTreeService.GetPublicState(player)
	local unlocked = PlayerDataService.GetSkillTreeUnlocked(player)
	local skills = {}
	for _, id in ipairs(ENABLED_ORDER) do
		local node = getNode(id)
		if node then
			table.insert(skills, {
				id = id,
				name = node.name,
				branch = node.branch,
				rank = unlocked[id] or 0,
				maxRank = node.maxRank,
				cost = node.costPerRank,
				description = node.description,
			})
		end
	end
	-- Phase 16C：暴露"可消费 allowlist"，供玩家 UI 区分可消费 vs Coming Soon（不改服务端校验）。
	local enabledIds = {}
	for _, id in ipairs(ENABLED_ORDER) do
		table.insert(enabledIds, id)
	end

	return {
		skillPoints = PlayerDataService.GetSkillPoints(player),
		totalPoints = SkillTreeService.GetTotalPoints(player),
		unlocked = unlocked,
		skills = skills, -- 兼容旧调试 UI
		enabledIds = enabledIds, -- Phase 16C：玩家 UI 用
	}
end

-- 玩家离开时清理去抖/锁状态。
function SkillTreeService.ClearPlayer(player)
	lastSpend[player] = nil
	spendLock[player] = nil
end

return SkillTreeService
