-- SkillTreeConfig: 玩家技能树配置（Phase 16A 设计脚手架 —— 纯数据）
-- 放在 ReplicatedStorage > Config > SkillTreeConfig (ModuleScript)
--
-- ⚠️ Phase 16A 边界：本模块仅为"设计脚手架"，【不被任何 gameplay 代码 require】，因此【不影响玩法】。
--    Phase 16B 才会接入：服务端消费 SkillPoints、持久化已解锁等级、应用前 3 个技能效果。
--    现在加入它只是为了把 schema 落到可编译的代码里，给 16B 一个确定、可计算的起点。
--
-- ---------- 节点 schema（每个技能节点的字段） ----------
--   id            string  唯一 id（约定：branchPrefix_name）
--   branch        string  所属分支（见 Branches 的 key）
--   name          string  显示名
--   description   string  说明（含每级数值，仅供显示）
--   nodeType      string  "Minor" | "Major" | "Keystone"
--                         设计意图：Minor 常 5/5；Major 通常 1/1（本表用于多级专精节点）；Keystone 1/1 且需深度投资。
--                         仅为设计/UI 强调用，不由 maxRank 强制。
--   maxRank       number  最大等级（rank 0..maxRank）
--   costPerRank   number  升一级消耗的技能点（Phase 16A 统一为定值；未来可换 costFormula(rank)）
--   requirements  table   结构化解锁条件（见下）—— 取代松散的 prerequisites：
--                   prerequisiteNodes    array  { { id=string, rank=number }, ... }（空=无）
--                   requiredBranchPoints number 投入【本分支】的总等级需 >= 此值（动态计算，不持久化）
--                   requiredTotalPoints  number 投入【全部分支】的总等级需 >= 此值（动态计算，不持久化）
--   modifiers     table   机器可读的效果定义（Phase 16B 的 SkillEffectResolver 由此计算）：
--                   [ModifierKey] = { base=number, perRank=number, applyMethod=string }
--                   value(rank) = base + rank * perRank
--                   applyMethod：
--                     "additive"       百分比/概率类加成，同 key 多来源【相加】，消费方按 ×(1+Σ) 或 +Σ 使用
--                     "flat"           直接加到基础数值（如 +1 基地血量）
--                     "flag"           rank>=1 即开启的布尔效果（如"每局一次"）
--                     "multiplicative" 预留：每来源各 ×(1+value)（MVP 节点未用）
--   effectType    string  人类可读标签 / 兼容用（路由提示）；数值真相在 modifiers
--   appliesTo     string  作用对象（reward/tower/pet/base…），hook 路由提示
--   ui            table   人工编排的布局元数据（UI 不应仅靠 prerequisites 自动排版）：
--                   gridX number, gridY number, icon string
--   tags          array   可选：未来检索/分类
--
-- 客户端永远只发"花费意图"（skillId）；rank/cost/分支点/总点/校验全部在服务端（Phase 16B）。
-- 派生量（branchPoints / totalPoints / 已投点数）一律【动态计算】自 Unlocked + 本配置，【不持久化】，避免脱同步。

local SkillTreeConfig = {}

-- ---------- 分支（4 大玩家技能分支） ----------
-- 注：原 "Survival" 已按评审意见更名为 "Defense"（本作核心是"防守基地"，非玩家角色生存）。
SkillTreeConfig.Branches = {
	Economy = { order = 1, displayName = "Economy", blurb = "金币与经验产出" },
	Tower = { order = 2, displayName = "Tower", blurb = "防御塔强化" },
	Pet = { order = 3, displayName = "Pet", blurb = "宠物强化" },
	Defense = { order = 4, displayName = "Defense", blurb = "基地防御与续航" },
}

-- ---------- 节点（MVP 初始节点示例；数值可调） ----------
SkillTreeConfig.Nodes = {
	-- ===== Economy（钩入奖励结算：RewardService / onEnemyKilled） =====
	{
		id = "eco_kill_coins",
		branch = "Economy",
		name = "Kill Coin Bonus",
		description = "击杀金币 +5% / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			CoinMultiplier = { base = 0, perRank = 0.05, applyMethod = "additive" },
		},
		effectType = "coin_mult",
		appliesTo = "kill_coins",
		ui = { gridX = 1, gridY = 1, icon = "" },
		tags = { "economy", "coins" },
	},
	{
		id = "eco_xp_bonus",
		branch = "Economy",
		name = "XP Bonus",
		description = "击杀经验 +5% / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			XPMultiplier = { base = 0, perRank = 0.05, applyMethod = "additive" },
		},
		effectType = "xp_mult",
		appliesTo = "kill_xp",
		ui = { gridX = 2, gridY = 1, icon = "" },
		tags = { "economy", "xp" },
	},
	{
		id = "eco_boss_bounty",
		branch = "Economy",
		name = "Boss Bounty",
		description = "Boss 奖励（金币与经验）+10% / 级。",
		nodeType = "Major",
		maxRank = 3,
		costPerRank = 2,
		requirements = {
			prerequisiteNodes = { { id = "eco_kill_coins", rank = 2 } },
			requiredBranchPoints = 3,
			requiredTotalPoints = 0,
		},
		modifiers = {
			BossRewardMultiplier = { base = 0, perRank = 0.10, applyMethod = "additive" },
		},
		effectType = "boss_reward_mult",
		appliesTo = "boss_kill_rewards",
		ui = { gridX = 1, gridY = 2, icon = "" },
		tags = { "economy", "boss" },
	},

	-- ===== Tower（钩入 TowerService 的每塔属性解析） =====
	{
		id = "twr_damage",
		branch = "Tower",
		name = "Tower Damage",
		description = "防御塔伤害 +5% / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			TowerDamageMultiplier = { base = 0, perRank = 0.05, applyMethod = "additive" },
		},
		effectType = "tower_damage_mult",
		appliesTo = "tower",
		ui = { gridX = 4, gridY = 1, icon = "" },
		tags = { "tower", "damage" },
	},
	{
		id = "twr_range",
		branch = "Tower",
		name = "Tower Range",
		description = "防御塔射程 +3% / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			TowerRangeMultiplier = { base = 0, perRank = 0.03, applyMethod = "additive" },
		},
		effectType = "tower_range_mult",
		appliesTo = "tower",
		ui = { gridX = 5, gridY = 1, icon = "" },
		tags = { "tower", "range" },
	},
	{
		id = "twr_attack_speed",
		branch = "Tower",
		name = "Tower Attack Speed",
		description = "防御塔攻击速度 +3% / 级（缩短攻击间隔）。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			TowerAttackSpeedMultiplier = { base = 0, perRank = 0.03, applyMethod = "additive" },
		},
		effectType = "tower_attackspeed_mult",
		appliesTo = "tower",
		ui = { gridX = 5, gridY = 2, icon = "" },
		tags = { "tower", "attackspeed" },
	},
	{
		id = "twr_build_discount",
		branch = "Tower",
		name = "Build Discount",
		description = "建造防御塔花费 -2% / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = {
			prerequisiteNodes = { { id = "twr_damage", rank = 1 } },
			requiredBranchPoints = 2,
			requiredTotalPoints = 0,
		},
		modifiers = {
			-- 折扣：value 为"减少比例"，消费方按 cost*(1-Σ) 使用（需下限保护）。
			TowerCostReduction = { base = 0, perRank = 0.02, applyMethod = "additive" },
		},
		effectType = "tower_cost_mult",
		appliesTo = "tower_cost",
		ui = { gridX = 4, gridY = 2, icon = "" },
		tags = { "tower", "economy" },
	},

	-- ===== Pet（钩入 PetService / CombatService 的宠物属性解析） =====
	{
		id = "pet_damage",
		branch = "Pet",
		name = "Pet Damage",
		description = "宠物伤害 +5% / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			PetDamageMultiplier = { base = 0, perRank = 0.05, applyMethod = "additive" },
		},
		effectType = "pet_damage_mult",
		appliesTo = "pet",
		ui = { gridX = 7, gridY = 1, icon = "" },
		tags = { "pet", "damage" },
	},
	{
		id = "pet_attack_speed",
		branch = "Pet",
		name = "Pet Attack Speed",
		description = "宠物攻击速度 +3% / 级（缩短攻击间隔）。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			PetAttackSpeedMultiplier = { base = 0, perRank = 0.03, applyMethod = "additive" },
		},
		effectType = "pet_attackspeed_mult",
		appliesTo = "pet",
		ui = { gridX = 8, gridY = 1, icon = "" },
		tags = { "pet", "attackspeed" },
	},
	{
		id = "pet_boss_hunter",
		branch = "Pet",
		name = "Boss Hunter",
		description = "宠物对 Boss 伤害 +8% / 级。",
		nodeType = "Major",
		maxRank = 3,
		costPerRank = 2,
		requirements = {
			prerequisiteNodes = { { id = "pet_damage", rank = 2 } },
			requiredBranchPoints = 3,
			requiredTotalPoints = 0,
		},
		modifiers = {
			PetDamageVsBossMultiplier = { base = 0, perRank = 0.08, applyMethod = "additive" },
		},
		effectType = "pet_damage_vs_boss_mult",
		appliesTo = "pet_vs_boss",
		ui = { gridX = 7, gridY = 2, icon = "" },
		tags = { "pet", "boss" },
	},

	-- ===== Defense（钩入 WaveService / 基地血量逻辑）—— 原 "Survival" 更名 =====
	{
		id = "def_base_reinforce",
		branch = "Defense",
		name = "Base Reinforcement",
		description = "基地最大血量 +1 / 级。",
		nodeType = "Minor",
		maxRank = 5,
		costPerRank = 1,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 0, requiredTotalPoints = 0 },
		modifiers = {
			BaseMaxHpFlat = { base = 0, perRank = 1, applyMethod = "flat" },
		},
		effectType = "base_max_hp_flat",
		appliesTo = "base",
		ui = { gridX = 10, gridY = 1, icon = "" },
		tags = { "defense", "base" },
	},
	{
		id = "def_leak_reduction",
		branch = "Defense",
		name = "Leak Reduction",
		description = "敌人逃逸时有 10% / 级 的概率不扣基地血量（上限 100%）。",
		nodeType = "Major",
		maxRank = 3,
		costPerRank = 2,
		requirements = { prerequisiteNodes = {}, requiredBranchPoints = 2, requiredTotalPoints = 0 },
		modifiers = {
			LeakIgnoreChance = { base = 0, perRank = 0.10, applyMethod = "additive" },
		},
		effectType = "leak_ignore_chance",
		appliesTo = "base_leak",
		ui = { gridX = 11, gridY = 1, icon = "" },
		tags = { "defense", "base" },
	},
	{
		id = "def_second_chance",
		branch = "Defense",
		name = "Second Chance",
		description = "每局一次：基地将被摧毁时，改为以 1 点血量存活。（未来效果）",
		nodeType = "Keystone",
		maxRank = 1,
		costPerRank = 3,
		requirements = {
			prerequisiteNodes = { { id = "def_base_reinforce", rank = 3 } },
			requiredBranchPoints = 5,
			requiredTotalPoints = 10,
		},
		modifiers = {
			SurviveOncePerRun = { base = 0, perRank = 1, applyMethod = "flag" },
		},
		effectType = "survive_once_per_run",
		appliesTo = "base",
		ui = { gridX = 10, gridY = 2, icon = "" },
		tags = { "defense", "clutch", "future" },
	},
}

-- ---------- 多树前向兼容（仅设计，不实现宠物树） ----------
-- 未来会有多棵树：玩家树、各宠物树等。Phase 16A 仅定义 "Player" 树；
-- 通过 GetTree(treeId) 命名空间化，使将来加 "Pet_Toasty" 等不需重构。
-- 示例（未来）：SkillTreeConfig.GetTree("Player") / SkillTreeConfig.GetTree("Pet_Toasty")
function SkillTreeConfig.GetTree(treeId)
	if treeId == nil or treeId == "Player" then
		return {
			id = "Player",
			Branches = SkillTreeConfig.Branches,
			Nodes = SkillTreeConfig.Nodes,
		}
	end
	return nil -- 未来的宠物树等尚未定义（Phase 16A 不实现）
end

-- ---------- 只读查询（纯函数，无副作用；不被 gameplay 调用前不影响任何逻辑） ----------

-- 按 id 取节点（找不到返回 nil）。
function SkillTreeConfig.GetById(skillId)
	for _, node in ipairs(SkillTreeConfig.Nodes) do
		if node.id == skillId then
			return node
		end
	end
	return nil
end

-- 取某分支下的全部节点（顺序同 Nodes；只读）。
function SkillTreeConfig.GetByBranch(branchKey)
	local out = {}
	for _, node in ipairs(SkillTreeConfig.Nodes) do
		if node.branch == branchKey then
			table.insert(out, node)
		end
	end
	return out
end

return SkillTreeConfig
