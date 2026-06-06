-- MainUI (LocalScript)
-- Place under StarterGui > MainUI. Builds the MVP client UI in code.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local playerDataRemote = Net.PlayerDataRemote()
local taskRemote = Net.TaskRemote()

-- ===================== Build UI =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Position = UDim2.fromOffset(16, 16)
panel.Size = UDim2.fromOffset(340, 294)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(75, 82, 110)
panelStroke.Transparency = 0.35
panelStroke.Thickness = 1
panelStroke.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 14)
padding.PaddingBottom = UDim.new(0, 14)
padding.PaddingLeft = UDim.new(0, 14)
padding.PaddingRight = UDim.new(0, 14)
padding.Parent = panel

local order = 0
local function nextOrder()
	order += 1
	return order
end

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.LayoutOrder = nextOrder()
titleLabel.Size = UDim2.new(1, 0, 0, 26)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 20
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Pet Defense"
titleLabel.Parent = panel

local function makeStatRow(name, labelText, valueText)
	local row = Instance.new("Frame")
	row.Name = name .. "Row"
	row.LayoutOrder = nextOrder()
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = Color3.fromRGB(31, 34, 46)
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0
	row.Parent = panel

	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local rowPadding = Instance.new("UIPadding")
	rowPadding.PaddingLeft = UDim.new(0, 10)
	rowPadding.PaddingRight = UDim.new(0, 10)
	rowPadding.Parent = row

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(0.45, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(177, 184, 204)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 14
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = row

	local value = Instance.new("TextLabel")
	value.Name = "Value"
	value.Position = UDim2.new(0.45, 0, 0, 0)
	value.Size = UDim2.new(0.55, 0, 1, 0)
	value.BackgroundTransparency = 1
	value.TextColor3 = Color3.fromRGB(248, 249, 255)
	value.Font = Enum.Font.GothamBold
	value.TextSize = 18
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextTruncate = Enum.TextTruncate.AtEnd
	value.Text = valueText
	value.Parent = row

	return value
end

local function makeLabel(name, text, height, textSize, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = nextOrder()
	label.Size = UDim2.new(1, 0, 0, height)
	label.BackgroundTransparency = 1
	label.TextColor3 = color or Color3.fromRGB(240, 240, 245)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = textSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Text = text
	label.Parent = panel
	return label
end

local coinsLabel = makeStatRow("Coins", "Coins", "--")
local levelLabel = makeStatRow("Level", "Level", "--")
local xpLabel = makeStatRow("XP", "XP", "-- / --")
local taskTitleLabel = makeLabel("TaskTitleLabel", "Current Task: --", 42, 16)
local taskProgLabel = makeLabel("TaskProgressLabel", "Progress: --", 24, 15, Color3.fromRGB(205, 211, 230))

local feedbackLabel = Instance.new("TextLabel")
feedbackLabel.Name = "RewardFeedbackLabel"
feedbackLabel.LayoutOrder = nextOrder()
feedbackLabel.Size = UDim2.new(1, 0, 0, 26)
feedbackLabel.BackgroundTransparency = 1
feedbackLabel.TextColor3 = Color3.fromRGB(126, 244, 162)
feedbackLabel.Font = Enum.Font.GothamBold
feedbackLabel.TextSize = 17
feedbackLabel.TextTransparency = 1
feedbackLabel.TextXAlignment = Enum.TextXAlignment.Center
feedbackLabel.Text = ""
feedbackLabel.Parent = panel

local feedbackScale = Instance.new("UIScale")
feedbackScale.Scale = 1
feedbackScale.Parent = feedbackLabel

local doButton = Instance.new("TextButton")
doButton.Name = "DoActionButton"
doButton.LayoutOrder = nextOrder()
doButton.Size = UDim2.new(1, 0, 0, 44)
doButton.BackgroundColor3 = Color3.fromRGB(62, 119, 222)
doButton.TextColor3 = Color3.fromRGB(255, 255, 255)
doButton.Font = Enum.Font.GothamBold
doButton.TextSize = 18
doButton.AutoButtonColor = true
doButton.Text = "Do Action"
doButton.Parent = panel

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 8)
buttonCorner.Parent = doButton

local buttonStroke = Instance.new("UIStroke")
buttonStroke.Color = Color3.fromRGB(150, 185, 255)
buttonStroke.Transparency = 0.45
buttonStroke.Thickness = 1
buttonStroke.Parent = doButton

-- ===================== UI Update =====================
local function updateData(data)
	if not data then
		return
	end
	coinsLabel.Text = string.format("%d", data.Coins or 0)
	levelLabel.Text = string.format("%d", data.Level or 1)
	xpLabel.Text = string.format("%d / %d", data.XP or 0, data.XpForNextLevel or 100)
end

local function updateTask(taskData)
	if not taskData then
		taskTitleLabel.Text = "Current Task: None"
		taskProgLabel.Text = "Progress: --"
		return
	end
	taskTitleLabel.Text = "Current Task: " .. tostring(taskData.title)
	taskProgLabel.Text = string.format("Progress: %d / %d", taskData.progress or 0, taskData.goal or 0)
end

local feedbackToken = 0
local function showReward(reward)
	if not reward then
		return
	end
	feedbackLabel.Text = string.format("+%d Coins, +%d XP!", reward.coinsAdded or 0, reward.xpAdded or 0)
	feedbackLabel.TextTransparency = 1
	feedbackScale.Scale = 0.95
	feedbackToken += 1
	local myToken = feedbackToken

	local showTween = TweenService:Create(
		feedbackLabel,
		TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			TextTransparency = 0,
		}
	)
	local scaleTween = TweenService:Create(
		feedbackScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{
			Scale = 1,
		}
	)
	showTween:Play()
	scaleTween:Play()

	task.delay(2.5, function()
		if myToken == feedbackToken then
			local hideTween = TweenService:Create(
				feedbackLabel,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					TextTransparency = 1,
				}
			)
			local hideScaleTween = TweenService:Create(
				feedbackScale,
				TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{
					Scale = 1.03,
				}
			)
			hideTween:Play()
			hideScaleTween:Play()
			hideTween.Completed:Wait()
			if myToken == feedbackToken then
				feedbackLabel.Text = ""
				feedbackScale.Scale = 1
			end
		end
	end)
end

-- ===================== Wiring =====================
playerDataRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Update" then
		updateData(payload)
	end
end)

taskRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Update" then
		updateTask(payload)
	elseif action == "Reward" then
		showReward(payload)
	end
end)

doButton.Activated:Connect(function()
	taskRemote:FireServer("DoAction")
end)

-- Request current state once at startup so the UI is initialized even if an initial server push was missed.
playerDataRemote:FireServer("Request")
taskRemote:FireServer("Request")
