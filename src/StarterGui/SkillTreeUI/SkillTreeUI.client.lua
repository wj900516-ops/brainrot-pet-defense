-- SkillTreeUI (LocalScript)
-- 放在 StarterGui > SkillTreeUI > SkillTreeUI (.client.lua => 客户端 LocalScript)
-- Phase 16C：面向玩家的技能树面板 MVP（独立 ScreenGui，【不改 MainUI】）。
-- 按 K 开关；顶部 4 个分支 Tab（Economy/Tower/Pet/Defense），下方技能卡片列表。
-- 客户端只发"消费意图"（RequestState / SpendPoint+skillId）；从不发送 rank/cost/点数/伤害/奖励。
-- 静态树结构（名称/分支/花费/上限/说明）从 ReplicatedStorage 的 SkillTreeConfig 读取（仅显示用）；
-- 等级/点数/可消费 allowlist 来自服务端 SkillRemote "State"。服务端始终是权威。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local skillRemote = Net.SkillRemote()

-- 读取配置（仅显示用；服务端仍权威）。
local SkillTreeConfig
do
	local ok, result = pcall(function()
		local config = ReplicatedStorage:WaitForChild("Config", 10)
		local module = config and config:WaitForChild("SkillTreeConfig", 10)
		return module and require(module)
	end)
	if ok and type(result) == "table" then
		SkillTreeConfig = result
	end
end

-- 分支顺序（优先用配置的 order；缺失则兜底）。
local BRANCH_ORDER = { "Economy", "Tower", "Pet", "Defense" }
if SkillTreeConfig and type(SkillTreeConfig.Branches) == "table" then
	local list = {}
	for key, meta in pairs(SkillTreeConfig.Branches) do
		table.insert(list, { key = key, order = (type(meta) == "table" and meta.order) or 99 })
	end
	if #list > 0 then
		table.sort(list, function(a, b)
			if a.order ~= b.order then
				return a.order < b.order
			end
			return a.key < b.key
		end)
		BRANCH_ORDER = {}
		for _, item in ipairs(list) do
			table.insert(BRANCH_ORDER, item.key)
		end
	end
end

local function branchNodes(branchKey)
	if SkillTreeConfig and SkillTreeConfig.GetByBranch then
		return SkillTreeConfig.GetByBranch(branchKey)
	end
	return {}
end

-- ===================== 状态 =====================
local state = { skillPoints = 0, unlocked = {}, enabled = {} } -- enabled: set { [id]=true }
local currentBranch = BRANCH_ORDER[1] or "Economy"

-- ===================== UI =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "SkillTreeUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 96
screenGui.Enabled = true
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(440, 360)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
panel.BackgroundTransparency = 0.04
panel.BorderSizePixel = 0
panel.Visible = false -- 默认隐藏；按 K 打开
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 12)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(95, 105, 140)
panelStroke.Transparency = 0.3
panelStroke.Parent = panel

-- 顶部标题栏。
local titleBar = Instance.new("Frame")
titleBar.Name = "TitleBar"
titleBar.Size = UDim2.new(1, 0, 0, 44)
titleBar.BackgroundTransparency = 1
titleBar.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(0.55, 0, 1, 0)
title.Position = UDim2.fromOffset(16, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "Skill Tree"
title.Parent = titleBar

local spLabel = Instance.new("TextLabel")
spLabel.Name = "SkillPoints"
spLabel.AnchorPoint = Vector2.new(1, 0.5)
spLabel.Position = UDim2.new(1, -52, 0.5, 0)
spLabel.Size = UDim2.fromOffset(150, 24)
spLabel.BackgroundTransparency = 1
spLabel.Font = Enum.Font.GothamBold
spLabel.TextSize = 15
spLabel.TextXAlignment = Enum.TextXAlignment.Right
spLabel.TextColor3 = Color3.fromRGB(126, 244, 162)
spLabel.Text = "SP: --"
spLabel.Parent = titleBar

local closeBtn = Instance.new("TextButton")
closeBtn.Name = "Close"
closeBtn.AnchorPoint = Vector2.new(1, 0.5)
closeBtn.Position = UDim2.new(1, -12, 0.5, 0)
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 16
closeBtn.Text = "X"
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.BackgroundColor3 = Color3.fromRGB(70, 50, 60)
closeBtn.Parent = titleBar
local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 6)
closeCorner.Parent = closeBtn

-- 分支 Tab 行。
local tabsBar = Instance.new("Frame")
tabsBar.Name = "Tabs"
tabsBar.Position = UDim2.fromOffset(12, 50)
tabsBar.Size = UDim2.new(1, -24, 0, 30)
tabsBar.BackgroundTransparency = 1
tabsBar.Parent = panel
local tabsLayout = Instance.new("UIListLayout")
tabsLayout.FillDirection = Enum.FillDirection.Horizontal
tabsLayout.Padding = UDim.new(0, 6)
tabsLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabsLayout.Parent = tabsBar

-- 卡片滚动区。
local cards = Instance.new("ScrollingFrame")
cards.Name = "Cards"
cards.Position = UDim2.fromOffset(12, 88)
cards.Size = UDim2.new(1, -24, 1, -136)
cards.BackgroundTransparency = 1
cards.BorderSizePixel = 0
cards.ScrollBarThickness = 6
cards.CanvasSize = UDim2.new(0, 0, 0, 0)
cards.AutomaticCanvasSize = Enum.AutomaticSize.Y
cards.Parent = panel
local cardsLayout = Instance.new("UIListLayout")
cardsLayout.Padding = UDim.new(0, 8)
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Parent = cards

-- 底部提示 / toast。
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 1)
toast.Position = UDim2.new(0.5, 0, 1, -12)
toast.Size = UDim2.new(1, -24, 0, 22)
toast.BackgroundTransparency = 1
toast.Font = Enum.Font.GothamMedium
toast.TextSize = 14
toast.TextColor3 = Color3.fromRGB(220, 220, 230)
toast.Text = "Press K to close"
toast.Parent = panel

local toastToken = 0
local function showToast(text, isError)
	toast.Text = text
	toast.TextColor3 = isError and Color3.fromRGB(255, 130, 130) or Color3.fromRGB(126, 244, 162)
	toastToken += 1
	local myToken = toastToken
	task.delay(2.5, function()
		if myToken == toastToken then
			toast.Text = "Press K to close"
			toast.TextColor3 = Color3.fromRGB(220, 220, 230)
		end
	end)
end

-- ===================== 渲染 =====================
local tabButtons = {}

local function refreshTabStyles()
	for branchKey, btn in pairs(tabButtons) do
		local active = (branchKey == currentBranch)
		btn.BackgroundColor3 = active and Color3.fromRGB(80, 110, 170) or Color3.fromRGB(45, 48, 62)
		btn.TextColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(200, 205, 220)
	end
end

local function makeCard(node)
	local rank = state.unlocked[node.id] or 0
	local maxRank = node.maxRank or 0
	local cost = node.costPerRank or 0
	local enabled = state.enabled[node.id] == true
	local atMax = rank >= maxRank
	local canAfford = state.skillPoints >= cost

	local card = Instance.new("Frame")
	card.Name = node.id
	card.LayoutOrder = #cards:GetChildren()
	card.Size = UDim2.new(1, -6, 0, 76)
	card.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
	card.BorderSizePixel = 0
	card.Parent = cards
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 8)
	cc.Parent = card
	local cpad = Instance.new("UIPadding")
	cpad.PaddingTop = UDim.new(0, 8)
	cpad.PaddingBottom = UDim.new(0, 8)
	cpad.PaddingLeft = UDim.new(0, 10)
	cpad.PaddingRight = UDim.new(0, 10)
	cpad.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -90, 0, 18)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextColor3 = enabled and Color3.fromRGB(245, 246, 255) or Color3.fromRGB(150, 152, 165)
	nameLabel.Text = string.format("%s  (%s)", node.name or node.id, node.branch or "")
	nameLabel.Parent = card

	local descLabel = Instance.new("TextLabel")
	descLabel.Position = UDim2.fromOffset(0, 20)
	descLabel.Size = UDim2.new(1, -90, 0, 18)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 12
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = Color3.fromRGB(180, 184, 200)
	descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	descLabel.Text = node.description or ""
	descLabel.Parent = card

	local meta = Instance.new("TextLabel")
	meta.Position = UDim2.fromOffset(0, 40)
	meta.Size = UDim2.new(1, -90, 0, 16)
	meta.BackgroundTransparency = 1
	meta.Font = Enum.Font.GothamMedium
	meta.TextSize = 12
	meta.TextXAlignment = Enum.TextXAlignment.Left
	meta.TextColor3 = Color3.fromRGB(160, 165, 185)
	meta.Text = string.format("Rank %d / %d    Cost %d", rank, maxRank, cost)
	meta.Parent = card

	-- 右侧动作区。
	if not enabled then
		local lock = Instance.new("TextLabel")
		lock.AnchorPoint = Vector2.new(1, 0.5)
		lock.Position = UDim2.new(1, 0, 0.5, 0)
		lock.Size = UDim2.fromOffset(78, 28)
		lock.BackgroundColor3 = Color3.fromRGB(50, 52, 64)
		lock.Font = Enum.Font.GothamBold
		lock.TextSize = 11
		lock.TextColor3 = Color3.fromRGB(190, 190, 200)
		lock.Text = "Coming Soon"
		lock.TextWrapped = true
		lock.Parent = card
		local lc = Instance.new("UICorner")
		lc.CornerRadius = UDim.new(0, 6)
		lc.Parent = lock
		return
	end

	local button = Instance.new("TextButton")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(78, 30)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.Parent = card
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = button

	if atMax then
		button.Text = "MAX"
		button.BackgroundColor3 = Color3.fromRGB(60, 62, 74)
		button.AutoButtonColor = false
		button.Active = false
	elseif not canAfford then
		button.Text = "+ " .. tostring(cost)
		button.BackgroundColor3 = Color3.fromRGB(58, 58, 70)
		button.AutoButtonColor = false
		button.Active = false
	else
		button.Text = "+ " .. tostring(cost)
		button.BackgroundColor3 = Color3.fromRGB(70, 120, 90)
		button.AutoButtonColor = true
		button.Active = true
		button.MouseButton1Click:Connect(function()
			-- 只发意图；服务端校验 + 去抖。
			skillRemote:FireServer("SpendPoint", node.id)
		end)
	end
end

local function render()
	spLabel.Text = string.format("SP: %d", state.skillPoints)
	refreshTabStyles()
	for _, child in ipairs(cards:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, node in ipairs(branchNodes(currentBranch)) do
		makeCard(node)
	end
end

-- 构建分支 Tab。
for index, branchKey in ipairs(BRANCH_ORDER) do
	local btn = Instance.new("TextButton")
	btn.Name = "Tab_" .. branchKey
	btn.LayoutOrder = index
	btn.Size = UDim2.new(0, 100, 1, 0)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.Text = branchKey
	btn.TextColor3 = Color3.fromRGB(200, 205, 220)
	btn.BackgroundColor3 = Color3.fromRGB(45, 48, 62)
	btn.Parent = tabsBar
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(0, 6)
	tc.Parent = btn
	tabButtons[branchKey] = btn
	btn.MouseButton1Click:Connect(function()
		currentBranch = branchKey
		render()
	end)
end

-- ===================== 开关 =====================
local function setOpen(open)
	panel.Visible = open
	if open then
		skillRemote:FireServer("RequestState") -- 打开时拉取最新
		render()
	end
end

closeBtn.MouseButton1Click:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.K then
		setOpen(not panel.Visible)
	end
end)

-- ===================== 接线 =====================
local REASON_TEXT = {
	not_enough_points = "Not enough Skill Points",
	max_rank = "Already at max rank",
	not_implemented = "Coming soon",
	too_fast = "Slow down",
	busy = "Busy — try again",
	prereq_node = "Requirements not met",
	prereq_branch = "Requirements not met",
	prereq_total = "Requirements not met",
}

skillRemote.OnClientEvent:Connect(function(action, payload)
	if action == "State" then
		if type(payload) == "table" then
			state.skillPoints = payload.skillPoints or 0
			state.unlocked = (type(payload.unlocked) == "table") and payload.unlocked or {}
			state.enabled = {}
			if type(payload.enabledIds) == "table" then
				for _, id in ipairs(payload.enabledIds) do
					state.enabled[id] = true
				end
			end
			if panel.Visible then
				render()
			end
		end
	elseif action == "Result" then
		local ok = payload and payload.success == true
		if ok then
			showToast(string.format("Upgraded -> rank %d", payload.rank or 0), false)
			-- 服务端成功后会主动再推一次 "State"，UI 会自动刷新。
		else
			local reason = (payload and payload.reason) or ""
			showToast(REASON_TEXT[reason] or ("Unavailable (" .. reason .. ")"), true)
		end
	end
end)

-- 启动时请求一次（即使面板未开，先缓存状态；打开时也会再请求）。
skillRemote:FireServer("RequestState")

print("[SkillTreeUI] loaded — press K to open the skill tree")
