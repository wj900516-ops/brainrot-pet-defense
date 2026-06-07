-- PetUI (LocalScript)
-- 放在 StarterGui > PetUI > PetUI (.client.lua => 客户端 LocalScript)
-- Phase 7：极简宠物界面 —— 列出拥有的宠物、显示是否装备、提供 Equip/Unequip。
-- 客户端只发"意图"（EquipPet/UnequipPet + uid）；所有校验与状态变更都在服务端。
-- 纯代码构建，独立 ScreenGui，不改动 MainUI / 后端。
--
-- 点击可靠性（Studio Play Solo 鼠标不触发 Activated）：
--   * 非按钮 GuiObject 全部 Active=false，避免透明 Frame/Label 挡点击。
--   * 保留 Activated + MouseButton1Click，并加 UserInputService 矩形命中后备。
--   * 所有点击路径共享去抖，避免后备与原生按钮双触发。
--
-- 键盘快捷键（临时 MVP/可访问性后备；仍只发意图，服务端仍是唯一真相）：
--   * P：打开/关闭宠物面板（任何时候）。
--   * E：面板打开时，装备"列表中第一只"宠物。
--   * U：面板打开时，卸下"列表中第一只已装备"宠物。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Net = require(ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Net"))
local petRemote = Net.PetRemote()

local DEBOUNCE_SEC = 0.2
local debounceExpiry = {}
local rowButtons = {}

local function tryPetUIClick(actionKey, fn, debugSource)
	local now = os.clock()
	if now < (debounceExpiry[actionKey] or 0) then
		return false
	end
	debounceExpiry[actionKey] = now + DEBOUNCE_SEC
	if debugSource then
		print(debugSource)
	end
	fn()
	return true
end

local function isGuiChainVisible(guiObject)
	local obj = guiObject
	while obj do
		if obj:IsA("GuiObject") and not obj.Visible then
			return false
		end
		obj = obj.Parent
	end
	return true
end

local function pointInGuiObject(guiObject, screenPoint)
	if not guiObject or not guiObject.Parent then
		return false
	end
	if not isGuiChainVisible(guiObject) then
		return false
	end
	local ap = guiObject.AbsolutePosition
	local as = guiObject.AbsoluteSize
	if as.X <= 0 or as.Y <= 0 then
		return false
	end
	return screenPoint.X >= ap.X
		and screenPoint.X <= ap.X + as.X
		and screenPoint.Y >= ap.Y
		and screenPoint.Y <= ap.Y + as.Y
end

local function getScreenPoint(input)
	if input.UserInputType == Enum.UserInputType.Touch then
		return Vector2.new(input.Position.X, input.Position.Y)
	end
	return UserInputService:GetMouseLocation()
end

-- 同时绑定 Activated 与 MouseButton1Click，并去抖，避免两者对同一次点击重复触发。
local function bindClick(button, actionKey, fn, debugLabel)
	local function handler()
		tryPetUIClick(actionKey, fn, "[PetUI] normal button Activated: " .. debugLabel)
	end
	button.Activated:Connect(handler)
	button.MouseButton1Click:Connect(handler)
end

-- ===================== 构建 UI =====================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PetUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 1000
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- 开关按钮：屏幕中右边缘（避开顶栏 inset 与底部 Studio UI），大尺寸易点击。
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "PetsToggle"
toggleButton.AnchorPoint = Vector2.new(1, 0.5)
toggleButton.Position = UDim2.new(1, -16, 0.5, 0)
toggleButton.Size = UDim2.fromOffset(150, 52)
toggleButton.BackgroundColor3 = Color3.fromRGB(70, 130, 220)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 18
toggleButton.Text = "Pets (P)"
toggleButton.AutoButtonColor = true
toggleButton.Active = true
toggleButton.Selectable = true
toggleButton.ZIndex = 200
toggleButton.Parent = screenGui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton
local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(150, 185, 255)
toggleStroke.Thickness = 1
toggleStroke.Parent = toggleButton

-- 面板：屏幕正中（清晰可见、行按钮居中易点击）。默认隐藏。
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.fromOffset(340, 380)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 30)
panel.BackgroundTransparency = 0.03
panel.BorderSizePixel = 0
panel.Visible = false
panel.Active = false
panel.ZIndex = 100
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(90, 110, 160)
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- 标题 + 快捷键提示。
local header = Instance.new("TextLabel")
header.Name = "Header"
header.Size = UDim2.new(1, -20, 0, 26)
header.Position = UDim2.fromOffset(12, 10)
header.BackgroundTransparency = 1
header.TextColor3 = Color3.fromRGB(255, 255, 255)
header.Font = Enum.Font.GothamBold
header.TextSize = 18
header.TextXAlignment = Enum.TextXAlignment.Left
header.Text = "My Pets"
header.Active = false
header.ZIndex = 101
header.Parent = panel

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.Size = UDim2.new(1, -20, 0, 16)
hint.Position = UDim2.fromOffset(12, 36)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.fromRGB(150, 158, 180)
hint.Font = Enum.Font.Gotham
hint.TextSize = 12
hint.TextXAlignment = Enum.TextXAlignment.Left
hint.Text = "Click a button, or press E=equip / U=unequip first pet"
hint.Active = false
hint.ZIndex = 101
hint.Parent = panel

-- 滚动列表容器。
local list = Instance.new("ScrollingFrame")
list.Name = "List"
list.Position = UDim2.fromOffset(12, 58)
list.Size = UDim2.new(1, -24, 1, -70)
list.BackgroundTransparency = 1
list.BorderSizePixel = 0
list.ScrollBarThickness = 4
list.CanvasSize = UDim2.new()
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.Active = false
list.ZIndex = 101
list.Parent = panel

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = list

-- ===================== 渲染 =====================
local currentPets = {}

local function clearRows()
	table.clear(rowButtons)
	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
end

local function sendEquip(uid)
	petRemote:FireServer("EquipPet", uid) -- 只发意图
end

local function sendUnequip(uid)
	petRemote:FireServer("UnequipPet", uid) -- 只发意图
end

local function makeRow(pet, order)
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.Size = UDim2.new(1, 0, 0, 50)
	row.BackgroundColor3 = Color3.fromRGB(31, 34, 46)
	row.BorderSizePixel = 0
	row.Active = false
	row.ZIndex = 101
	row.Parent = list
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 6)
	rowCorner.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Position = UDim2.fromOffset(10, 5)
	nameLabel.Size = UDim2.new(1, -120, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.fromRGB(248, 249, 255)
	nameLabel.Font = Enum.Font.GothamMedium
	nameLabel.TextSize = 15
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = tostring(pet.displayName)
	nameLabel.Active = false
	nameLabel.ZIndex = 102
	nameLabel.Parent = row

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Position = UDim2.fromOffset(10, 26)
	statusLabel.Size = UDim2.new(0.5, 0, 0, 18)
	statusLabel.BackgroundTransparency = 1
	statusLabel.TextColor3 = pet.equipped and Color3.fromRGB(126, 244, 162) or Color3.fromRGB(177, 184, 204)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.TextSize = 13
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Text = pet.equipped and "Equipped" or "Not equipped"
	statusLabel.Active = false
	statusLabel.ZIndex = 102
	statusLabel.Parent = row

	local actionButton = Instance.new("TextButton")
	actionButton.AnchorPoint = Vector2.new(1, 0.5)
	actionButton.Position = UDim2.new(1, -8, 0.5, 0)
	actionButton.Size = UDim2.fromOffset(100, 36)
	actionButton.BackgroundColor3 = pet.equipped and Color3.fromRGB(120, 80, 80) or Color3.fromRGB(62, 119, 222)
	actionButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionButton.Font = Enum.Font.GothamBold
	actionButton.TextSize = 14
	actionButton.AutoButtonColor = true
	actionButton.Active = true
	actionButton.Selectable = true
	actionButton.Text = pet.equipped and "Unequip" or "Equip"
	actionButton.ZIndex = 200
	actionButton.Parent = row
	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 5)
	btnCorner.Parent = actionButton

	local equipped = pet.equipped
	local uid = pet.uid
	local actionLabel = equipped and "Unequip" or "Equip"
	local actionKey = "row_" .. uid

	table.insert(rowButtons, {
		button = actionButton,
		uid = uid,
		equipped = equipped,
	})

	bindClick(actionButton, actionKey, function()
		if equipped then
			sendUnequip(uid)
		else
			sendEquip(uid)
		end
	end, actionLabel .. " " .. uid)

	return row
end

local function render()
	clearRows()
	if #currentPets == 0 then
		local empty = Instance.new("Frame")
		empty.LayoutOrder = 1
		empty.Size = UDim2.new(1, 0, 0, 30)
		empty.BackgroundTransparency = 1
		empty.Active = false
		empty.ZIndex = 101
		empty.Parent = list
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.TextColor3 = Color3.fromRGB(177, 184, 204)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 13
		lbl.Text = "No pets owned."
		lbl.Active = false
		lbl.ZIndex = 102
		lbl.Parent = empty
		return
	end
	for i, pet in ipairs(currentPets) do
		makeRow(pet, i)
	end
end

-- ===================== 开关逻辑 =====================
local function setOpen(open)
	panel.Visible = open
	if open then
		petRemote:FireServer("RequestPets") -- 打开时立即请求最新列表
		render()
	end
	print("[PetUI] panel ->", open)
end

local function toggle()
	setOpen(not panel.Visible)
end

local function runRowAction(entry)
	if entry.equipped then
		sendUnequip(entry.uid)
	else
		sendEquip(entry.uid)
	end
end

local function tryMouseFallback(screenPoint)
	if pointInGuiObject(toggleButton, screenPoint) then
		return tryPetUIClick("toggle", toggle, "[PetUI] mouse fallback hit toggle")
	end
	if not panel.Visible then
		return false
	end
	for i = #rowButtons, 1, -1 do
		local entry = rowButtons[i]
		if pointInGuiObject(entry.button, screenPoint) then
			local label = entry.equipped and "Unequip" or "Equip"
			return tryPetUIClick(
				"row_" .. entry.uid,
				function()
					runRowAction(entry)
				end,
				string.format("[PetUI] mouse fallback hit row button: %s %s", label, entry.uid)
			)
		end
	end
	return false
end

-- 键盘后备：装备列表中第一只宠物（面板打开时）。
local function equipFirst()
	local pet = currentPets[1]
	if pet then
		print("[PetUI] keyboard E -> equip", pet.uid)
		sendEquip(pet.uid)
	end
end

-- 键盘后备：卸下列表中第一只"当前已装备"的宠物（面板打开时）。
local function unequipFirstEquipped()
	for _, pet in ipairs(currentPets) do
		if pet.equipped then
			print("[PetUI] keyboard U -> unequip", pet.uid)
			sendUnequip(pet.uid)
			return
		end
	end
	print("[PetUI] keyboard U -> no equipped pet")
end

-- ===================== 接线 =====================
petRemote.OnClientEvent:Connect(function(action, payload)
	if action == "Pets" then
		currentPets = payload or {}
		if panel.Visible then
			render()
		end
	end
end)

bindClick(toggleButton, "toggle", toggle, "toggle")

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		tryMouseFallback(getScreenPoint(input))
		return
	end

	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.P then
		toggle()
	elseif input.KeyCode == Enum.KeyCode.E then
		if panel.Visible then
			equipFirst()
		end
	elseif input.KeyCode == Enum.KeyCode.U then
		if panel.Visible then
			unequipFirstEquipped()
		end
	end
end)

-- 启动时请求一次（即使面板未打开，拿到数据备用）。
petRemote:FireServer("RequestPets")
print("[PetUI] loaded — click center-right 'Pets' button or press P (E=equip / U=unequip when open)")
