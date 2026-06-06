-- ServerInit (Script)
-- 放在 ServerScriptService > ServerInit (.server.lua => 服务端 Script)
-- 服务端引导脚本：连接 PlayerAdded、初始化数据、分配起始任务、接线 Remote。
-- 这是唯一同时认识各 Service 与 Net 的"编排层"，Service 自身保持纯净。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- 加载服务（Services 文件夹与本脚本同在 ServerScriptService 下）
local Services = script.Parent:WaitForChild("Services")
local PlayerDataService = require(Services:WaitForChild("PlayerDataService"))
local TaskService = require(Services:WaitForChild("TaskService"))

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

-- TaskRemote：客户端请求当前任务 或 触发一次行动（MVP 测试用）
taskRemote.OnServerEvent:Connect(function(player, action)
	if action == "Request" then
		pushTask(player)
	elseif action == "DoAction" then
		local result = TaskService.AddProgress(player, 1)
		if not result then
			return
		end
		-- 若本次行动完成了任务 → 推送奖励反馈
		if result.completed then
			taskRemote:FireClient(player, "Reward", result.reward)
		end
		-- 始终推送最新任务与数据，UI 即时刷新
		pushTask(player)
		pushData(player)
	end
end)

print("[ServerInit] MVP core loop ready.")
