-- SkillEffectResolver (ModuleScript)
-- 放在 ServerScriptService > Services > SkillEffectResolver
-- Phase 16B：把玩家已投的技能等级聚合成【缓存的修正量】，供各系统在解析属性/结算时 O(1) 读取。
--
-- 设计：
--   * 缓存 per-player，仅在以下时机【重建】：玩家加载/加入、成功消费技能点、（未来）respec。
--     —— 绝不在每次塔攻击/宠物攻击时遍历整棵树；攻击时只做 O(1) 的 GetNumber/GetFlag。
--   * 数值真相来自 SkillTreeConfig 各节点的 modifiers：[ModifierKey] = { base, perRank, applyMethod }，
--     value(rank) = base + rank*perRank。每个 ModifierKey 在配置中只用一种 applyMethod（保持口径单一）。
--   * applyMethod：additive（百分比/概率，累加）/ flat（平铺加）/ multiplicative（各 ×(1+v)）/ flag（布尔）。
--
-- 修正量计算次序（严格）：Base → flat add → additive percent → multiplicative percent → clamp。
-- 见 ResolveStat（通用 stat 解析 + 夹紧）。Phase 16B 的 3 个技能均为 additive 百分比。

local PlayerDataService = require(script.Parent.PlayerDataService)

local SkillEffectResolver = {}

-- ---------- 加载 SkillTreeConfig（容错；缺失则无任何修正，绝不崩） ----------
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
			warn("[SkillEffectResolver] require SkillTreeConfig 失败：" .. tostring(result))
		end
	else
		warn("[SkillEffectResolver] 未找到 ReplicatedStorage.Config.SkillTreeConfig，无技能修正")
	end
end

-- ---------- 缓存 ----------
-- cache[player] = { numbers = { [key] = number }, flags = { [key] = bool } }
--   numbers[key] = flat + additive + (multFactor - 1)
--     —— 因每个 key 只用一种 applyMethod，三者中至多一项非零，故该和即该 key 的"单一修正量（delta）"：
--        百分比类 → 消费方用 base*(1+delta)；平铺类 → 消费方用 base+delta。
local cache = setmetatable({}, { __mode = "k" }) -- 弱键：玩家对象回收时自动释放

-- ---------- 数值工具 ----------

-- 通用夹紧。
function SkillEffectResolver.Clamp(value, minValue, maxValue)
	if type(value) ~= "number" then
		return value
	end
	if minValue ~= nil then
		value = math.max(minValue, value)
	end
	if maxValue ~= nil then
		value = math.min(maxValue, value)
	end
	return value
end

-- 严格次序的 stat 解析：Base → flat → additive% → multiplicative% → clamp。
-- opts = { flat=0, additive=0, mult=0, min=nil, max=nil }
function SkillEffectResolver.ResolveStat(base, opts)
	opts = opts or {}
	local v = (type(base) == "number") and base or 0
	v = v + (opts.flat or 0)
	v = v * (1 + (opts.additive or 0))
	v = v * (1 + (opts.mult or 0))
	return SkillEffectResolver.Clamp(v, opts.min, opts.max)
end

-- 花费折扣的夹紧规则（Phase 16B 不启用相关技能，但架构先就位）：
-- 折扣后的花费【绝不低于基础花费的 20%】。reduction 为"减少比例"（0..1）。
function SkillEffectResolver.ApplyCostReduction(baseCost, reduction)
	baseCost = (type(baseCost) == "number") and baseCost or 0
	reduction = (type(reduction) == "number") and math.max(0, reduction) or 0
	local floorCost = math.ceil(baseCost * 0.2)
	return math.max(floorCost, math.ceil(baseCost * (1 - reduction)))
end

-- ---------- 重建 / 清除 ----------

-- 按玩家当前已投等级重建缓存。无数据/无配置 → 空缓存（GetNumber 取默认值）。
function SkillEffectResolver.Rebuild(player)
	local numbers = {}
	local flags = {}

	if SkillTreeConfig and SkillTreeConfig.GetById then
		local unlocked = PlayerDataService.GetSkillTreeUnlocked(player) -- { [skillId] = rank } 拷贝
		-- 每 key 的中间累加器：flat 累加、additive 累加、mult 连乘 (1+v)、flag 取或。
		local acc = {} -- [key] = { flat, additive, mult, flag }
		for skillId, rank in pairs(unlocked) do
			if type(rank) == "number" and rank > 0 then
				local node = SkillTreeConfig.GetById(skillId)
				if node and type(node.modifiers) == "table" then
					for key, mod in pairs(node.modifiers) do
						if type(mod) == "table" then
							local base = (type(mod.base) == "number") and mod.base or 0
							local perRank = (type(mod.perRank) == "number") and mod.perRank or 0
							local value = base + rank * perRank
							local rec = acc[key]
							if not rec then
								rec = { flat = 0, additive = 0, mult = 1, flag = false }
								acc[key] = rec
							end
							local method = mod.applyMethod
							if method == "flat" then
								rec.flat += value
							elseif method == "multiplicative" then
								rec.mult *= (1 + value)
							elseif method == "flag" then
								rec.flag = true -- rank>0 即开启
							else -- "additive"（默认）
								rec.additive += value
							end
						end
					end
				end
			end
		end
		for key, rec in pairs(acc) do
			numbers[key] = rec.flat + rec.additive + (rec.mult - 1)
			if rec.flag then
				flags[key] = true
			end
		end
	end

	cache[player] = { numbers = numbers, flags = flags }
end

-- 清除某玩家缓存（玩家离开时调用）。
function SkillEffectResolver.Clear(player)
	cache[player] = nil
end

-- ---------- 读取（O(1)，攻击/结算热路径使用） ----------

-- 取某 ModifierKey 的聚合修正量（delta）。无缓存/无该 key → defaultValue（默认 0）。
-- 百分比类 key：消费方用 base*(1+GetNumber)；平铺类 key：消费方用 base+GetNumber。
function SkillEffectResolver.GetNumber(player, modifierKey, defaultValue)
	local entry = cache[player]
	if entry then
		local v = entry.numbers[modifierKey]
		if v ~= nil then
			return v
		end
	end
	return defaultValue or 0
end

-- 取某 ModifierKey 的布尔旗标（applyMethod = "flag"）。无则 false。
function SkillEffectResolver.GetFlag(player, modifierKey)
	local entry = cache[player]
	return (entry and entry.flags[modifierKey]) == true
end

return SkillEffectResolver
