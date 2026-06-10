-- SkillTreeDebug (LocalScript)
-- 放在 StarterGui > SkillTreeDebug > SkillTreeDebug (.client.lua => 客户端 LocalScript)
-- Phase 16B：极简技能树调试 UI（独立 ScreenGui，【不改 MainUI】）。
-- 列出 3 个启用技能，显示等级/上限/花费，点 [+] 发送"消费意图"；服务端校验后回推结果。
-- 客户端只发意图（RequestState / SpendPoint+skillId）；从不发送 rank/cost/点数/伤害/奖励。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local skillRemote = Net.SkillRemote()

-- ===================== UI（独立 ScreenGui，右上角；避开左下 MainUI 与左上聊天） =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SkillTreeDebugUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 90
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, 16)
panel.Size = UDim2.fromOffset(280, 210)
panel.BackgroundColor3 = Color3.fromRGB(22, 20, 30)
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(95, 80, 120)
stroke.Transparency = 0.35
stroke.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 12)
padding.PaddingBottom = UDim.new(0, 12)
padding.PaddingLeft = UDim.new(0, 12)
padding.PaddingRight = UDim.new(0, 12)
padding.Parent = panel

local order = 0
local function nextOrder()
	order += 1
	return order
end

local title = Instance.new("TextLabel")
title.Name = "Title"
title.LayoutOrder = nextOrder()
title.Size = UDim2.new(1, 0, 0, 22)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 16
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "Skill Tree (Debug)"
title.Parent = panel

local spLabel = Instance.new("TextLabel")
spLabel.Name = "SkillPoints"
spLabel.LayoutOrder = nextOrder()
spLabel.Size = UDim2.new(1, 0, 0, 20)
spLabel.BackgroundTransparency = 1
spLabel.Font = Enum.Font.GothamMedium
spLabel.TextSize = 14
spLabel.TextXAlignment = Enum.TextXAlignment.Left
spLabel.TextColor3 = Color3.fromRGB(126, 244, 162)
spLabel.Text = "Skill Points: --"
spLabel.Parent = panel

-- 行容器（每次收到 State 重建内容）。
local rows = Instance.new("Frame")
rows.Name = "Rows"
rows.LayoutOrder = nextOrder()
rows.Size = UDim2.new(1, 0, 0, 110)
rows.BackgroundTransparency = 1
rows.Parent = panel
local rowsLayout = Instance.new("UIListLayout")
rowsLayout.Padding = UDim.new(0, 4)
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Parent = rows

local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.LayoutOrder = nextOrder()
toast.Size = UDim2.new(1, 0, 0, 18)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamMedium
toast.TextSize = 13
toast.TextXAlignment = Enum.TextXAlignment.Left
toast.TextColor3 = Color3.fromRGB(220, 220, 230)
toast.Text = ""
toast.Parent = panel

local toastToken = 0
local function showToast(text, isError)
	toast.Text = text
	toast.TextColor3 = isError and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(126, 244, 162)
	toastToken += 1
	local myToken = toastToken
	task.delay(2.5, function()
		if myToken == toastToken then
			toast.Text = ""
		end
	end)
end

-- ===================== 渲染 =====================
local function clearRows()
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function makeRow(skill, skillPoints)
	local rank = skill.rank or 0
	local maxRank = skill.maxRank or 0
	local cost = skill.cost or 0
	local atMax = rank >= maxRank
	local canAfford = skillPoints >= cost
	local spendable = (not atMax) and canAfford

	local row = Instance.new("Frame")
	row.Name = skill.id
	row.LayoutOrder = nextOrder()
	row.Size = UDim2.new(1, 0, 0, 32)
	row.BackgroundTransparency = 1
	row.Parent = rows

	local info = Instance.new("TextLabel")
	info.Size = UDim2.new(1, -56, 1, 0)
	info.Position = UDim2.fromOffset(0, 0)
	info.BackgroundTransparency = 1
	info.Font = Enum.Font.Gotham
	info.TextSize = 13
	info.TextXAlignment = Enum.TextXAlignment.Left
	info.TextColor3 = Color3.fromRGB(235, 235, 245)
	info.Text = string.format("%s  %d/%d  (cost %d)", skill.name or skill.id, rank, maxRank, cost)
	info.Parent = row

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(48, 26)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.Text = atMax and "MAX" or "+"
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.BackgroundColor3 = spendable and Color3.fromRGB(70, 120, 90) or Color3.fromRGB(60, 60, 70)
	button.AutoButtonColor = spendable
	button.Active = spendable
	button.Parent = row
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = button

	if spendable then
		button.MouseButton1Click:Connect(function()
			-- 只发意图；服务端校验 + 去抖。
			skillRemote:FireServer("SpendPoint", skill.id)
		end)
	end
end

local function render(state)
	if type(state) ~= "table" then
		return
	end
	local sp = state.skillPoints or 0
	spLabel.Text = string.format("Skill Points: %d", sp)
	clearRows()
	if type(state.skills) == "table" then
		for _, skill in ipairs(state.skills) do
			makeRow(skill, sp)
		end
	end
end

-- ===================== 接线 =====================
skillRemote.OnClientEvent:Connect(function(action, payload)
	if action == "State" then
		render(payload)
	elseif action == "Result" then
		local ok = payload and payload.success == true
		local reason = (payload and payload.reason) or ""
		if ok then
			showToast(string.format("Upgraded %s -> %d", tostring(payload.skillId), payload.rank or 0), false)
		else
			showToast("Rejected: " .. reason, true)
		end
	end
end)

-- 启动时请求一次状态（服务端加入时也会主动推一次）。
skillRemote:FireServer("RequestState")

print("[SkillTreeDebug] loaded — spend points into the 3 enabled skills")
