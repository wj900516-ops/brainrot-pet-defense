-- ServerInit (Script)
-- 放在 ServerScriptService > ServerInit (.server.lua => 服务端 Script)
-- 服务端引导脚本：连接 PlayerAdded、初始化数据、分配起始任务、接线 Remote。
-- 这是唯一同时认识各 Service 与 Net 的"编排层"，Service 自身保持纯净。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 调试开关：是否接受客户端的 "DoAction" 调试请求。
-- 默认 false —— Phase 2 由真实的训练假人循环驱动进度，调试按钮通道关闭。
local ENABLE_DEBUG_DO_ACTION = false

-- Phase 7：宠物"变更类"动作（EquipPet/UnequipPet）的每玩家服务端去抖（防刷）。
-- 在顶部声明，使 onPlayerRemoving 可清理其状态（local 必须先于使用处定义）。
local PET_MUTATION_COOLDOWN_SECONDS = 0.5
local lastPetMutation = {} -- [player] = os.clock()

-- 加载服务（Services 文件夹与本脚本同在 ServerScriptService 下）
local Services = script.Parent:WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local TaskService = require(Services:WaitForChild("TaskService"))
local GameEventService = require(Services:WaitForChild("GameEventService"))
local DummyTargetService = require(Services:WaitForChild("DummyTargetService"))
local PetService = require(Services:WaitForChild("PetService"))
local RewardService = require(Services:WaitForChild("RewardService")) -- Phase 8：仅调用既有契约，不修改
local EnemyService = require(Services:WaitForChild("EnemyService"))
local WaveService = require(Services:WaitForChild("WaveService"))
local CombatService = require(Services:WaitForChild("CombatService"))
local TowerService = require(Services:WaitForChild("TowerService"))
local SkillEffectResolver = require(Services:WaitForChild("SkillEffectResolver")) -- Phase 16B
local SkillTreeService = require(Services:WaitForChild("SkillTreeService")) -- Phase 16B

-- 加载远程入口（服务端在此创建 RemoteEvent 实例）
local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local playerDataRemote = Net.PlayerDataRemote()
local taskRemote = Net.TaskRemote()
local petRemote = Net.PetRemote()
local towerRemote = Net.TowerRemote()
local restartRemote = Net.RestartRemote()
local skillRemote = Net.SkillRemote() -- Phase 16B

-- Phase 13：向客户端推送会话是否失败（用于显示/隐藏"按 R 重开"提示）。
local function pushSessionState(player)
	local payload = { failed = WaveService.IsFailed() }
	if player then
		restartRemote:FireClient(player, "SessionState", payload)
	else
		restartRemote:FireAllClients("SessionState", payload)
	end
end

-- ---------- 向客户端推送 ----------
local function pushData(player)
	playerDataRemote:FireClient(player, "Update", PlayerDataService.GetPublicData(player))
end

-- Phase 16B：推送技能树公开状态（点数 / 各启用技能的等级 / 上限 / 花费）给调试 UI。
local function pushSkillState(player)
	skillRemote:FireClient(player, "State", SkillTreeService.GetPublicState(player))
end

local function pushTask(player)
	taskRemote:FireClient(player, "Update", TaskService.GetCurrentTask(player))
end

-- 推送公开宠物列表。安全数据来自 PlayerDataService（uid/petId/equipped），
-- displayName 在此由 PetService（PetConfig）注入，避免 PlayerDataService 依赖 PetConfig。
local function pushPets(player)
	local pets = PlayerDataService.GetPublicPets(player)
	for _, entry in ipairs(pets) do
		entry.displayName = PetService.GetDisplayName(entry.petId)
	end
	petRemote:FireClient(player, "Pets", pets)
end

-- ---------- 统一的"进度结果 -> 推送"出口 ----------
-- TaskService 负责全部决策（是否加进度 / 是否完成 / 是否发奖励 / 是否匹配），
-- 并返回一致的结果对象：{ progressed, completed, task, reward, reason }。
-- ServerInit 只负责把结果推送给客户端，保持编排层与 Service 的边界。
local function pushProgressResult(player, result)
	if not result then
		return
	end
	-- 完成时推送奖励反馈
	if result.completed and result.reward then
		taskRemote:FireClient(player, "Reward", result.reward)
	end
	-- 有进度变化（含完成后已切换到下一个任务）才推送，UI 即时刷新到最新任务/数据
	if result.progressed then
		-- 结果对象已带最新公开任务数据，直接复用（与再次 GetCurrentTask 等价，省一次查询）。
		if result.task ~= nil then
			taskRemote:FireClient(player, "Update", result.task)
		else
			pushTask(player)
		end
		pushData(player)
	end
end

-- ---------- 玩家生命周期 ----------
local function onPlayerAdded(player)
	-- 加载存档（会 yield；pcall + 有限重试 + 失败回退默认值，绝不崩服）。
	PlayerDataService.LoadData(player)

	-- 若玩家在加载期间离开，则不再恢复任务/推送 UI。
	if not player.Parent then
		return
	end

	-- Phase 6：确保拥有并装备起始宠物（首次/缺失时授予，不重复）。需在 SpawnPet 之前。
	PlayerDataService.EnsureStarterPet(player, PetService.GetStarterPetId())

	-- Phase 16B：技能树配置感知清洗（丢弃未知 id、按 maxRank 夹紧），再重建效果缓存。
	SkillTreeService.SanitizeOnLoad(player)
	SkillEffectResolver.Rebuild(player)

	-- 加载完成后再恢复任务状态（按存档 id/进度，或起始任务）。
	TaskService.RestoreOrAssign(player)

	-- 主动推送一次。若客户端此时尚未连接监听，客户端启动时也会再 "Request"。
	pushData(player)
	pushTask(player)

	-- Phase 5/6：根据已装备宠物数据生成宠物。
	PetService.SpawnPet(player)

	-- Phase 7：主动推送一次公开宠物列表（Pet UI 打开时也会再 RequestPets）。
	pushPets(player)

	-- Phase 13：推送当前会话状态（若已失败，客户端显示"按 R 重开"）。
	pushSessionState(player)

	-- Phase 16B：推送技能树初始状态给调试 UI（客户端打开时也会再 RequestState）。
	pushSkillState(player)
end

local function onPlayerRemoving(player)
	-- 先清理宠物（停止其攻击与跟随），再保存数据。
	PetService.DespawnPet(player)

	-- 离开时保存（pcall + 重试；加载失败的会话会自动跳过保存以免覆盖云端）。
	PlayerDataService.SaveData(player)
	PlayerDataService.ClearData(player)
	TaskService.ClearTask(player)
	lastPetMutation[player] = nil -- 清理宠物变更去抖状态
	SkillEffectResolver.Clear(player) -- Phase 16B：清效果缓存
	SkillTreeService.ClearPlayer(player) -- Phase 16B：清消费去抖/锁
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- 处理脚本加载前就已在场的玩家（Studio Play Solo 常见情况）。
-- 用 task.spawn 避免加载 yield 阻塞后续玩家的初始化。
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- 服务器关闭时保存所有在场玩家（Studio 停止 / 服务器关停）。
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerDataService.SaveData(player)
	end
end)

-- 启动周期自动保存（安全网；对 PlayerRemoving / BindToClose 的补充，不是替代）。
PlayerDataService.StartAutoSave()

-- Phase 5：启动宠物系统（每位玩家一只起始宠物，主人靠近假人时自动攻击）。
PetService.Start()

-- ---------- Remote 处理 ----------
-- PlayerDataRemote：客户端请求最新公开数据
playerDataRemote.OnServerEvent:Connect(function(player, action)
	if action == "Request" then
		pushData(player)
	end
end)

-- TaskRemote：客户端请求当前任务 或 触发一次【调试】行动
-- 注意："DoAction" 仅供调试按钮使用（客户端只是请求，进度仍由服务端决定）。
taskRemote.OnServerEvent:Connect(function(player, action)
	if action == "Request" then
		pushTask(player)
	elseif action == "DoAction" then
		-- 调试通道：仅在开关开启时生效；关闭时安全忽略（不发进度/奖励）。
		-- 注意：调试通道走通用 AddProgress（不做 type/target 匹配），仅供开发测试。
		if ENABLE_DEBUG_DO_ACTION then
			pushProgressResult(player, TaskService.AddProgress(player, 1))
		end
		-- 关闭状态下静默忽略，避免被刷请求时刷屏 Output。
	end
end)

-- ---------- Phase 2/3：真实游戏行动（训练假人 + 任务匹配） ----------
-- 监听服务端事件总线：假人被击败 -> 交给 TaskService 做 type/target 匹配与进度推进。
-- 仅当当前任务为 DefeatEnemy 且 target 匹配 enemyId 时才会加进度/发奖励；否则安全忽略。
-- DummyTargetService 不发奖励、不依赖 TaskService；匹配与奖励决策在 TaskService 完成。
GameEventService.EnemyDefeated.Event:Connect(function(player, enemyId)
	pushProgressResult(player, TaskService.HandleEnemyDefeated(player, enemyId))
end)

-- 生成训练假人（纯服务端 ClickDetector，无需新增 RemoteEvent）。
DummyTargetService.Start()

-- ---------- Phase 8：敌人波次 + 宠物战斗循环 ----------
-- 敌人击杀 -> 通过既有 RewardService 发奖励（窄适配：构造 reward 形状的表，不改 RewardService 契约），
-- 再推送最新玩家数据给客户端。CombatService 只做伤害判定，不发奖励、不写 DataStore。
local function onEnemyKilled(player, enemy)
	if not player or not enemy then
		return
	end
	-- 复用 RewardService.GiveReward(player, task)：task 只需带 rewardCoins/rewardXP 字段。
	-- Phase 15：击杀同时发放 XP（enemy.xpReward，服务端权威；普通小额、Boss 更高）。
	-- Phase 16B：eco_kill_coins 提升击杀金币（CoinMultiplier，服务端权威；普通与 Boss 击杀都生效）。
	--   仅作用于"击杀金币"；XP 不受影响（eco_xp_bonus 本阶段未启用）。逃逸不进此路径 → 不发金币/XP。
	local coinBonus = math.max(0, SkillEffectResolver.GetNumber(player, "CoinMultiplier", 0))
	local baseCoins = enemy.reward or 0
	-- 金币必须为整数：四舍五入（+0.5 下取整），使低基数下 rank 1 也有可见的 +5%（如 15 -> 16）。
	local coins = math.floor(baseCoins * (1 + coinBonus) + 0.5)
	local reward = RewardService.GiveReward(player, {
		rewardCoins = coins,
		rewardXP = enemy.xpReward or 0,
	})
	pushData(player) -- 刷新 MainUI 的金币/等级/经验/技能点

	-- Phase 15：QA 可见日志（XP 获得 / 升级 / 技能点）。
	if reward then
		print(string.format(
			"[Reward] %s 击杀 %s：+%d Coins，+%d XP（当前 XP %d，Level %d，SP %d）",
			player.Name,
			enemy.displayName or enemy.enemyId or "enemy",
			reward.coinsAdded or 0,
			reward.xpAdded or 0,
			reward.newXP or 0,
			reward.level or 1,
			reward.skillPoints or 0
		))
		if reward.leveledUp then
			print(string.format(
				"[Progression] %s 升级！现 Level %d，+%d 技能点（共 %d）",
				player.Name,
				reward.level or 1,
				reward.skillPointsAdded or 0,
				reward.skillPoints or 0
			))
		end
		-- 奖励反馈：复用既有 taskRemote "Reward" 通道（MainUI 已监听）。Phase 15 追加升级文本。
		taskRemote:FireClient(player, "Reward", reward)
	end
end

-- Phase 9：敌人逃逸（到达基地）→ WaveService 扣基地血量（逃逸不发奖励）。
EnemyService.Start({ onEscaped = WaveService.OnEnemyEscaped }) -- 敌人移动/清理 + 逃逸回调
CombatService.Start({ onEnemyKilled = onEnemyKilled }) -- 宠物→敌人战斗（击杀奖励，未改动）
-- Phase 9/13：波次 + 基地血量 + 失败条件；失败时通知客户端可重开。
WaveService.Start({
	onSessionFailed = function()
		pushSessionState() -- 广播：已失败 → 客户端显示"按 R 重开"
	end,
})
-- Phase 11/12：塔放置 + 塔攻击。击杀复用同一 onEnemyKilled 奖励通道；
-- DamageEnemy 的 alive 一次性守卫保证宠物/塔击杀同一敌人不重复发奖。
TowerService.Start({ onEnemyKilled = onEnemyKilled })

-- ---------- Phase 11：塔放置（服务端权威） ----------
-- 客户端只发 "PlaceTower" 意图；服务端读取玩家角色位置并校验后放置。
-- 客户端不能伪造位置/花费/拥有者，也不能免费造塔。
towerRemote.OnServerEvent:Connect(function(player, action, position)
	if action == "PlaceTower" then
		-- position 为客户端鬼影预览的地面落点（可空）；服务端完整校验，不信任客户端。
		local result = TowerService.TryPlaceTower(player, position)
		if result and result.success then
			pushData(player) -- 扣币后刷新 MainUI 金币
		end
		towerRemote:FireClient(player, "Result", result) -- 回推结果给客户端反馈
	end
	-- 未知 action：安全忽略。
end)

-- ---------- Phase 13：会话重开（服务端权威） ----------
-- 客户端只发 "Restart" 意图；仅在会话失败后允许。服务端清敌人/塔、重置基地/波次、重启刷怪。
-- 客户端不能直接设置波次/基地血量/金币/敌人状态。
restartRemote.OnServerEvent:Connect(function(player, action)
	if action == "Restart" then
		if not WaveService.IsFailed() then
			-- 运行中不允许重开（MVP）。
			restartRemote:FireClient(player, "Result", { success = false, reason = "run_active" })
			return
		end
		TowerService.ClearAll() -- 清所有塔（清后攻击循环不再遍历到它们）
		local ok = WaveService.ResetSession() -- 清敌人 + 重置基地/波次 + 重启刷怪
		pushSessionState() -- 广播最新会话状态（已不再失败）
		restartRemote:FireClient(player, "Result", { success = ok == true, reason = ok and "restarted" or "failed" })
	end
	-- 未知 action：安全忽略。
end)

-- ---------- Phase 7：宠物 UI 的装备/卸下（服务端权威） ----------
-- 客户端只发"意图"：RequestPets / EquipPet / UnequipPet(+uid)。
-- 所有校验与状态变更都在服务端；客户端不能授予宠物、不能直接改 Inventory/EquippedPets。
--
-- 服务端去抖：仅对"变更类"动作（EquipPet/UnequipPet）做每玩家冷却，安全忽略刷请求；
-- 不影响 RequestPets（只读）。被冷却拦截时直接返回，不改状态、不刷屏 Output。
-- （PET_MUTATION_COOLDOWN_SECONDS / lastPetMutation 在文件顶部声明，便于 onPlayerRemoving 清理。）
local function petMutationAllowed(player)
	local now = os.clock()
	local last = lastPetMutation[player]
	if last and (now - last) < PET_MUTATION_COOLDOWN_SECONDS then
		return false -- 冷却中：静默忽略
	end
	lastPetMutation[player] = now
	return true
end

petRemote.OnServerEvent:Connect(function(player, action, uid)
	if action == "RequestPets" then
		pushPets(player) -- 只读：不受去抖限制

	elseif action == "EquipPet" then
		-- 变更类动作：先过服务端去抖（防刷）。
		if not petMutationAllowed(player) then
			return
		end
		-- 校验：uid 为字符串 → 玩家拥有该 uid → 其 petId 在 PetConfig 中存在（否则无法生成）。
		if type(uid) ~= "string" then
			return
		end
		if not PlayerDataService.IsPetOwned(player, uid) then
			warn(string.format("[ServerInit] EquipPet 拒绝：玩家 %s 未拥有 uid '%s'", player.Name, tostring(uid)))
			return
		end

		-- 解析该 uid 的 petId，并校验其在 PetConfig 中存在（拒绝装备无法生成的过时宠物）。
		local petId
		for _, entry in ipairs(PlayerDataService.GetPets(player)) do
			if entry.uid == uid then
				petId = entry.petId
				break
			end
		end
		if not petId or not PetService.HasPet(petId) then
			warn(string.format("[ServerInit] EquipPet 拒绝：petId '%s' 在 PetConfig 中不存在（过时/缺失）", tostring(petId)))
			return
		end

		if PlayerDataService.EquipPet(player, uid) then
			PetService.RefreshPet(player)
			pushPets(player)
		end

	elseif action == "UnequipPet" then
		-- 变更类动作：先过服务端去抖（防刷）。
		if not petMutationAllowed(player) then
			return
		end
		if type(uid) ~= "string" then
			return
		end
		if PlayerDataService.UnequipPet(player, uid) then
			PetService.RefreshPet(player)
			pushPets(player)
		end
	end
	-- 未知 action：安全忽略。
end)

-- ---------- Phase 16B：技能树（服务端权威消费） ----------
-- 客户端只发意图：RequestState（只读）/ SpendPoint(+skillId)。
-- 所有 rank/cost/前置/点数判定都在 SkillTreeService；客户端不能伪造任何数值。
-- SkillTreeService 内置每玩家去抖（0.2s）+ 处理锁，防双击/宏重复扣点。
skillRemote.OnServerEvent:Connect(function(player, action, skillId)
	if action == "RequestState" then
		pushSkillState(player) -- 只读
	elseif action == "SpendPoint" then
		local result = SkillTreeService.TrySpend(player, skillId)
		if result and result.success then
			pushData(player) -- 刷新 MainUI 的技能点数字
			pushSkillState(player) -- 刷新调试 UI 的等级/点数
			print(string.format(
				"[SkillTree] %s 升级 %s -> rank %d（剩余 SP %d）",
				player.Name,
				tostring(result.skillId),
				result.rank or 0,
				result.skillPoints or 0
			))
		end
		skillRemote:FireClient(player, "Result", result) -- 成功/失败都回推（含 reason）
	end
	-- 未知 action：安全忽略。
end)

print("[ServerInit] Ready. Phase 16B skill tree MVP online.")
