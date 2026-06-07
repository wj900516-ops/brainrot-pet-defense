-- TowerPlacer (LocalScript)
-- 放在 StarterGui > TowerPlacer > TowerPlacer (.client.lua => 客户端 LocalScript)
-- Phase 11：塔放置输入（MVP）。按 T 发送"放置意图"；服务端读取角色位置并校验放置。
-- 客户端只发意图、不带位置/花费；所有决策在服务端。纯代码 UI（独立 ScreenGui），不改 MainUI。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local towerRemote = Net.TowerRemote()

-- ===================== 极简反馈 UI（独立 ScreenGui，非 MainUI） =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TowerPlacerUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 90
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- 底部提示：按 T 放置塔
local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0.5, 1)
hint.Position = UDim2.new(0.5, 0, 1, -16)
hint.Size = UDim2.fromOffset(260, 28)
hint.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
hint.BackgroundTransparency = 0.25
hint.TextColor3 = Color3.fromRGB(220, 224, 240)
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 14
hint.Text = "Press T to place a Tower (100 coins)"
hint.Parent = screenGui
local hintCorner = Instance.new("UICorner")
hintCorner.CornerRadius = UDim.new(0, 6)
hintCorner.Parent = hint

-- 结果 toast（短暂显示）
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -52)
toast.Size = UDim2.fromOffset(300, 28)
toast.BackgroundTransparency = 1
toast.TextColor3 = Color3.fromRGB(126, 244, 162)
toast.Font = Enum.Font.GothamBold
toast.TextSize = 16
toast.Text = ""
toast.Parent = screenGui

local toastToken = 0
local function showToast(text, isError)
	toast.Text = text
	toast.TextColor3 = isError and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(126, 244, 162)
	toastToken += 1
	local myToken = toastToken
	task.delay(2, function()
		if myToken == toastToken then
			toast.Text = ""
		end
	end)
end

-- reason -> 玩家可读文案
local REASON_TEXT = {
	placed = "Tower placed!",
	not_enough_coins = "Not enough coins",
	too_close_to_path = "Too close to the path",
	too_close_to_tower = "Too close to another tower",
	no_character = "Cannot place right now",
	no_data = "Cannot place right now",
}

-- ===================== 接线 =====================
towerRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Result" then
		local reason = payload and payload.reason or "no_data"
		local ok = payload and payload.success == true
		showToast(REASON_TEXT[reason] or (ok and "Tower placed!" or "Placement failed"), not ok)
		print("[TowerPlacer] result:", reason, "success=", tostring(ok))
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.T then
		towerRemote:FireServer("PlaceTower") -- 只发意图，不带位置/花费
	end
end)

print("[TowerPlacer] loaded — press T to place a Tower")
