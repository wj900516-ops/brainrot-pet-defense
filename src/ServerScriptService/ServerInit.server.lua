-- ServerInit (Script)
-- 放在 ServerScriptService > ServerInit (.server.lua => 服务端 Script)
-- 服务端引导脚本：连接 PlayerAdded、初始化数据、分配起始任务、接线 Remote。
-- 这是唯一同时认识各 Service 与 Net 的"编排层"，Service 自身保持纯净。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 调试开关：是否接受客户端的 "DoAction" 调试请求。
-- 默认 false —— Phase 2 由真实的训练假人循环驱动进度，调试按钮通道关闭。
local ENABLE_DEBUG_DO_ACTION = false

-- 加载服务（Services 文件夹与本脚本同在 ServerScriptService 下）
local Services = script.Parent:WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local TaskService = require(Services:WaitForChild("TaskService"))
local GameEventService = require(Services:WaitForChild("GameEventService"))
local DummyTargetService = require(Services:WaitForChild("DummyTargetService"))

-- 加载远程入口（服务端在此创建 RemoteEvent 实例）
local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local playerDataRemote = Net.PlayerDataRemote()
local taskRemote = Net.TaskRemote()

-- ---------- 向客户端推送 ----------
local function pushData(player)
	playerDataRemote:FireClient(player, "Update", PlayerDataService.GetPublicData(player))
end

local function pushTask(player)
	taskRemote:FireClient(player, "Update", TaskService.GetCurrentTask(player))
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

	-- 加载完成后再恢复任务状态（按存档 id/进度，或起始任务）。
	TaskService.RestoreOrAssign(player)

	-- 主动推送一次。若客户端此时尚未连接监听，客户端启动时也会再 "Request"。
	pushData(player)
	pushTask(player)
end

local function onPlayerRemoving(player)
	-- 离开时先保存（pcall + 重试；加载失败的会话会自动跳过保存以免覆盖云端）。
	PlayerDataService.SaveData(player)
	PlayerDataService.ClearData(player)
	TaskService.ClearTask(player)
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

print("[ServerInit] Ready. Phase 4 player data persistence online.")
