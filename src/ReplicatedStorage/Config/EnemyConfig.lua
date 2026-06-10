-- EnemyConfig: 敌人配置表
-- 放在 ReplicatedStorage > Config > EnemyConfig (ModuleScript)

local EnemyConfig = {
	LagBlob = {
		displayName  = "Lag Blob",
		health       = 24,       -- 血量（Phase 8 调平：50→24，保证宠物能在逃逸前击杀）
		speed        = 4,        -- 移动速度 studs/秒（Phase 8 调平：8→4，给宠物足够输出时间）
		baseDamage   = 1,        -- 到达基地时造成的伤害
		killReward   = 15,       -- 击杀奖励金币
		xpReward     = 20,       -- Phase 15：击杀奖励经验（普通怪：小额）
		-- 以后扩展:
		-- model     = "LagBlob",
		-- isBoss    = false,
	},

	-- Phase 14：Boss 里程碑（每 5 波）。基于现有敌人基础设施的占位 Boss：
	-- 更大体型 + 不同颜色 + "Boss" 名称，基础值由 WaveService 的 Boss 倍率按 tier 放大
	-- （最终 hp/speed/reward = 这里的基础值 × 当波倍率）。本阶段不加 Boss 技能/VFX。
	BossLagBlob = {
		displayName  = "Boss LagBlob",
		health       = 30,       -- Boss 基础血量（×Boss 倍率后远高于普通敌人）
		speed        = 4,        -- Boss 基础速度（×Boss 倍率后比普通敌人更慢）
		baseDamage   = 1,        -- 逃逸时对基地的伤害（与普通一致，仍走 OnEnemyEscaped 扣 1）
		killReward   = 18,       -- Boss 基础金币奖励（×Boss 倍率后远高于普通击杀）
		xpReward     = 30,       -- Phase 15：Boss 基础经验（×Boss 倍率 5+tier → 约 180/210/240…，远高于普通 20）
		size         = Vector3.new(6, 6, 6),         -- 更大体型（EnemyService 支持 size 覆盖）
		color        = Color3.fromRGB(150, 60, 200), -- 紫色，便于 QA 辨识 Boss
		isBoss       = true,
		-- 未来可扩展字段（Phase 14 仅预留形状，不影响玩法）：
		-- resistances  = { physical = 0, magic = 0 },
		-- abilities    = {},
		-- shapeVariant = "blob",
		-- skillSet     = {},
	},

	StinkyBreadBoss = {
		displayName  = "Stinky Bread Boss",
		health       = 300,
		speed        = 5,
		baseDamage   = 5,
		killReward   = 50,
		-- isBoss    = true,
	},
}

return EnemyConfig
