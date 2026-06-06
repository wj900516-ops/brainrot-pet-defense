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

-- ---------- 统一的"行动 -> 进度 -> 奖励 -> 推送"入口 ----------
-- 这是任何真实游戏行动（击败假人）与调试按钮共用的唯一进度通道。
-- 服务端独占：是否加进度、是否完成、是否发奖励都由这里决定。
local function grantActionProgress(player)
	local result = TaskService.AddProgress(player, 1)
	if not result then
		return
	end
	if result.completed then
		taskRemote:FireClient(player, "Reward", result.reward)
	end
	pushTask(player)
	pushData(player)
end

-- ---------- 玩家生命周期 ----------
local function onPlayerAdded(player)
	PlayerDataService.InitData(player)
	TaskService.AssignStarterTask(player)

	-- 主动推送一次。若客户端此时尚未连接监听，客户端启动时也会再 "Request"。
	pushData(player)
	pushTask(player)
end

local function onPlayerRemoving(player)
	PlayerDataService.ClearData(player)
	TaskService.ClearTask(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- 处理脚本加载前就已在场的玩家（Studio Play Solo 常见情况）
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

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
		if ENABLE_DEBUG_DO_ACTION then
			grantActionProgress(player)
		end
		-- 关闭状态下静默忽略，避免被刷请求时刷屏 Output。
	end
end)

-- ---------- Phase 2：真实游戏行动（训练假人） ----------
-- 监听服务端事件总线：假人被击败 -> 加一次进度（复用同一通道）。
-- DummyTargetService 不发奖励，奖励决策只发生在这里。
GameEventService.EnemyDefeated.Event:Connect(function(player, enemyId)
	grantActionProgress(player)
end)

-- 生成训练假人（纯服务端 ClickDetector，无需新增 RemoteEvent）。
DummyTargetService.Start()

print("[ServerInit] MVP core loop ready. Phase 2 dummy target online.")
