-- RunControl (LocalScript)
-- 放在 StarterGui > RunControl > RunControl (.client.lua => 客户端 LocalScript)
-- Phase 13：失败后按 R 重开会话。客户端只发"重开意图"；服务端校验（仅失败后允许）并执行。
-- 纯代码 UI（独立 ScreenGui），不改 MainUI。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local restartRemote = Net.RestartRemote()

-- ===================== UI（独立 ScreenGui，非 MainUI） =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RunControlUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 95
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- 失败提示：屏幕上方居中，仅在失败时显示。
local prompt = Instance.new("TextLabel")
prompt.Name = "RestartPrompt"
prompt.AnchorPoint = Vector2.new(0.5, 0)
prompt.Position = UDim2.new(0.5, 0, 0, 80)
prompt.Size = UDim2.fromOffset(360, 44)
prompt.BackgroundColor3 = Color3.fromRGB(40, 20, 24)
prompt.BackgroundTransparency = 0.1
prompt.TextColor3 = Color3.fromRGB(255, 150, 150)
prompt.Font = Enum.Font.GothamBold
prompt.TextSize = 20
prompt.Text = "BASE DESTROYED — Press R to Restart"
prompt.Visible = false
prompt.Parent = screenGui
local promptCorner = Instance.new("UICorner")
promptCorner.CornerRadius = UDim.new(0, 8)
promptCorner.Parent = prompt

-- 结果 toast。
local toast = Instance.new("TextLabel")
toast.Name = "Toast"
toast.AnchorPoint = Vector2.new(0.5, 0)
toast.Position = UDim2.new(0.5, 0, 0, 132)
toast.Size = UDim2.fromOffset(320, 28)
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

-- ===================== 状态 + 接线 =====================
local failed = false

restartRemote.OnClientEvent:Connect(function(action, payload)
	if action == "SessionState" then
		failed = payload and payload.failed == true
		prompt.Visible = failed
		if not failed then
			toast.Text = ""
		end
	elseif action == "Result" then
		local ok = payload and payload.success == true
		local reason = payload and payload.reason or ""
		if ok then
			showToast("Run restarted!", false)
		elseif reason == "run_active" then
			showToast("Run still active", true)
		else
			showToast("Restart failed", true)
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.R then
		-- 只发意图；服务端校验（仅失败后允许）。
		restartRemote:FireServer("Restart")
	end
end)

print("[RunControl] loaded — press R to restart after the base falls")
