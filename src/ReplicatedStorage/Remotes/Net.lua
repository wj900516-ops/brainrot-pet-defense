-- Net (ModuleScript)
-- 放在 ReplicatedStorage > Remotes > Net
-- 远程事件统一入口：服务端按需创建 RemoteEvent，客户端等待其出现。
--
-- 设计：本模块所在的文件夹 (script.Parent) 即 "Remotes" 文件夹；
-- 真正的 RemoteEvent 实例会作为 Net 的兄弟节点放在该文件夹下，
-- 因此无需在 Studio 里手动创建任何 RemoteEvent。
--
-- 服务端调用 PlayerDataRemote()/TaskRemote() 时会创建（若不存在）。
-- 客户端调用时会 WaitForChild 等待服务端创建完成。

local RunService = game:GetService("RunService")

local Net = {}

local folder = script.Parent -- "Remotes" 文件夹

Net.PlayerDataRemoteName = "PlayerDataRemote"
Net.TaskRemoteName = "TaskRemote"
Net.PetRemoteName = "PetRemote"
Net.TowerRemoteName = "TowerRemote"

-- 获取（服务端则创建）指定名称的 RemoteEvent。
local function getEvent(name)
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end

	if RunService:IsServer() then
		local ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
		return ev
	end

	-- 客户端：等待服务端创建
	return folder:WaitForChild(name)
end

function Net.PlayerDataRemote()
	return getEvent(Net.PlayerDataRemoteName)
end

function Net.TaskRemote()
	return getEvent(Net.TaskRemoteName)
end

function Net.PetRemote()
	return getEvent(Net.PetRemoteName)
end

function Net.TowerRemote()
	return getEvent(Net.TowerRemoteName)
end

return Net
