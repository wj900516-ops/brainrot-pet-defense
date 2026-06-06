-- TaskConfig (ModuleScript)
-- 放在 ReplicatedStorage > Config > TaskConfig
-- 任务配置表：定义起始任务链与可重复 fallback 任务。
-- 数据驱动，TaskService 据此分配/推进任务。
--
-- 每个任务定义字段：
--   id          : string  唯一标识
--   type        : string  任务类型（当前支持 "DefeatEnemy"）
--   target      : string? 目标标识（DefeatEnemy 时为敌人 id，如 "TrainingDummy"）
--   title       : string  显示给玩家的标题
--   goal        : number  需要的次数（>=1）
--   rewardCoins : number  完成奖励金币
--   rewardXP    : number  完成奖励经验
--
-- 扩展更多任务类型时（例如 "InteractTarget" / "EarnCoins"），
-- 在此追加定义，并在 TaskService 中为该 type 增加对应的事件匹配即可。

local TaskConfig = {}

-- 起始任务链：玩家按数组顺序依次推进。
TaskConfig.StarterChain = {
	{
		id = "defeat_training_dummy_1",
		type = "DefeatEnemy",
		target = "TrainingDummy",
		title = "Defeat 1 Training Dummy",
		goal = 1,
		rewardCoins = 50,
		rewardXP = 25,
	},
	{
		id = "defeat_training_dummy_3",
		type = "DefeatEnemy",
		target = "TrainingDummy",
		title = "Defeat 3 Training Dummies",
		goal = 3,
		rewardCoins = 150,
		rewardXP = 75,
	},
	-- 未来示例（暂不启用，避免过度设计）：
	-- {
	-- 	id = "interact_chest_1",
	-- 	type = "InteractTarget",
	-- 	target = "Chest",
	-- 	title = "Open a Chest",
	-- 	goal = 1,
	-- 	rewardCoins = 30,
	-- 	rewardXP = 10,
	-- },
}

-- 链结束后循环的可重复任务 id（指向链中某个任务）。
-- 留空 / 找不到时，TaskService 默认循环链中最后一个任务。
TaskConfig.RepeatableFallbackId = "defeat_training_dummy_3"

-- 便捷查表：id -> def（供其他消费者/文档使用；TaskService 内部会基于"已校验"的链另建查表）。
TaskConfig.ById = {}
for _, def in ipairs(TaskConfig.StarterChain) do
	TaskConfig.ById[def.id] = def
end

return TaskConfig
