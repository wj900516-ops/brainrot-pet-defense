-- SkillTreeConfig: 玩家技能树配置（Phase 16A 设计脚手架 —— 纯数据）
-- 放在 ReplicatedStorage > Config > SkillTreeConfig (ModuleScript)
--
-- ⚠️ Phase 16A 边界：本模块仅为"设计脚手架"，【不被任何 gameplay 代码 require】，因此【不影响玩法】。
--    Phase 16B 才会接入：服务端消费 SkillPoints、持久化已解锁等级、应用前 3 个技能效果。
--    现在加入它只是为了把 schema 落到可编译的代码里，给 16B 一个确定的起点。
--
-- ---------- 节点 schema（每个技能节点的字段） ----------
--   id                 string  唯一 id（约定：branchPrefix_name）
--   branch             string  所属分支（见 Branches 的 key）
--   name               string  显示名
--   description        string  说明（含每级数值）
--   maxRank            number  最大等级（rank 0..maxRank）
--   costPerRank        number  升一级消耗的技能点（Phase 16A 统一为定值；未来可换成 costFormula(rank)）
--   prerequisites      array   前置条件：{ { id = string, rank = number }, ... }（空表 = 无前置）
--   effectType         string  效果类型（供未来 SkillEffectResolver 分发；本阶段不消费）
--   effectValuePerRank number  每级效果增量（如 0.05 = +5%/级；1 = +1/级；语义由 effectType 决定）
--   appliesTo          string  效果作用对象（reward / tower / pet / base …，供 hook 点路由）
--   tags               array   可选：未来检索/分类用
--
-- 约定：所有数值"加成"为正；"折扣类"（如建造折扣）用 effectType 表达"减少"，数值仍为正的减少量。
-- 客户端永远只发"花费意图"（skillId）；rank/cost/校验全部在服务端（Phase 16B）。

local SkillTreeConfig = {}

-- ---------- 分支（4 大玩家技能分支） ----------
SkillTreeConfig.Branches = {
	Economy = { order = 1, displayName = "Economy", blurb = "金币与经验产出" },
	Tower = { order = 2, displayName = "Tower", blurb = "防御塔强化" },
	Pet = { order = 3, displayName = "Pet", blurb = "宠物强化" },
	Survival = { order = 4, displayName = "Survival", blurb = "基地与生存" },
}

-- ---------- 节点（MVP 初始节点示例；数值可调） ----------
SkillTreeConfig.Nodes = {
	-- ===== Economy（钩入奖励结算：RewardService / onEnemyKilled） =====
	{
		id = "eco_kill_coins",
		branch = "Economy",
		name = "Kill Coin Bonus",
		description = "击杀金币 +5% / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "coin_mult",
		effectValuePerRank = 0.05,
		appliesTo = "kill_coins",
		tags = { "economy", "coins" },
	},
	{
		id = "eco_xp_bonus",
		branch = "Economy",
		name = "XP Bonus",
		description = "击杀经验 +5% / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "xp_mult",
		effectValuePerRank = 0.05,
		appliesTo = "kill_xp",
		tags = { "economy", "xp" },
	},
	{
		id = "eco_boss_bounty",
		branch = "Economy",
		name = "Boss Bounty",
		description = "Boss 奖励（金币与经验）+10% / 级。",
		maxRank = 3,
		costPerRank = 2,
		prerequisites = { { id = "eco_kill_coins", rank = 2 } },
		effectType = "boss_reward_mult",
		effectValuePerRank = 0.10,
		appliesTo = "boss_kill_rewards",
		tags = { "economy", "boss" },
	},

	-- ===== Tower（钩入 TowerService 的每塔属性解析） =====
	{
		id = "twr_damage",
		branch = "Tower",
		name = "Tower Damage",
		description = "防御塔伤害 +5% / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "tower_damage_mult",
		effectValuePerRank = 0.05,
		appliesTo = "tower",
		tags = { "tower", "damage" },
	},
	{
		id = "twr_range",
		branch = "Tower",
		name = "Tower Range",
		description = "防御塔射程 +3% / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "tower_range_mult",
		effectValuePerRank = 0.03,
		appliesTo = "tower",
		tags = { "tower", "range" },
	},
	{
		id = "twr_attack_speed",
		branch = "Tower",
		name = "Tower Attack Speed",
		description = "防御塔攻击速度 +3% / 级（缩短攻击间隔）。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "tower_attackspeed_mult",
		effectValuePerRank = 0.03,
		appliesTo = "tower",
		tags = { "tower", "attackspeed" },
	},
	{
		id = "twr_build_discount",
		branch = "Tower",
		name = "Build Discount",
		description = "建造防御塔花费 -2% / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = { { id = "twr_damage", rank = 1 } },
		effectType = "tower_cost_mult",
		effectValuePerRank = 0.02, -- 减少量（正数表示"便宜 2%/级"）
		appliesTo = "tower_cost",
		tags = { "tower", "economy" },
	},

	-- ===== Pet（钩入 PetService / CombatService 的宠物属性解析） =====
	{
		id = "pet_damage",
		branch = "Pet",
		name = "Pet Damage",
		description = "宠物伤害 +5% / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "pet_damage_mult",
		effectValuePerRank = 0.05,
		appliesTo = "pet",
		tags = { "pet", "damage" },
	},
	{
		id = "pet_attack_speed",
		branch = "Pet",
		name = "Pet Attack Speed",
		description = "宠物攻击速度 +3% / 级（缩短攻击间隔）。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "pet_attackspeed_mult",
		effectValuePerRank = 0.03,
		appliesTo = "pet",
		tags = { "pet", "attackspeed" },
	},
	{
		id = "pet_boss_hunter",
		branch = "Pet",
		name = "Boss Hunter",
		description = "宠物对 Boss 伤害 +8% / 级。",
		maxRank = 3,
		costPerRank = 2,
		prerequisites = { { id = "pet_damage", rank = 2 } },
		effectType = "pet_damage_vs_boss_mult",
		effectValuePerRank = 0.08,
		appliesTo = "pet_vs_boss",
		tags = { "pet", "boss" },
	},

	-- ===== Survival（钩入 WaveService / 基地血量逻辑） =====
	{
		id = "sur_base_reinforce",
		branch = "Survival",
		name = "Base Reinforcement",
		description = "基地最大血量 +1 / 级。",
		maxRank = 5,
		costPerRank = 1,
		prerequisites = {},
		effectType = "base_max_hp_flat",
		effectValuePerRank = 1,
		appliesTo = "base",
		tags = { "survival", "base" },
	},
	{
		id = "sur_leak_reduction",
		branch = "Survival",
		name = "Leak Reduction",
		description = "敌人逃逸时有 10% / 级 的概率不扣基地血量。",
		maxRank = 3,
		costPerRank = 2,
		prerequisites = {},
		effectType = "leak_ignore_chance",
		effectValuePerRank = 0.10,
		appliesTo = "base_leak",
		tags = { "survival", "base" },
	},
	{
		id = "sur_second_chance",
		branch = "Survival",
		name = "Second Chance",
		description = "每局一次：基地将被摧毁时，改为以 1 点血量存活。（未来效果）",
		maxRank = 1,
		costPerRank = 3,
		prerequisites = { { id = "sur_base_reinforce", rank = 3 } },
		effectType = "survive_once_per_run",
		effectValuePerRank = 1,
		appliesTo = "base",
		tags = { "survival", "clutch", "future" },
	},
}

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

-- 取某分支下的全部节点（数组拷贝引用；只读）。
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
