-- Day13 Step1: 合成按钮 + 星级显示 + RemoteEvent（命令栏粘贴）
local RS = game:GetService("ReplicatedStorage")
local SG = game:GetService("StarterGui")

-- 1. RemoteEvent
local rm = RS:FindFirstChild("Remotes")
if not rm:FindFirstChild("MergeUnit") then Instance.new("RemoteEvent",rm).Name = "MergeUnit" end

-- 2. 在 InventoryFrame 每行加合成按钮 + 星级显示
local ui = SG:FindFirstChild("MainUI")
if not ui then return end
local f = ui:FindFirstChild("InventoryFrame")
if not f then return end

-- 加大面板
f.Size = UDim2.new(0, 380, 0, 440)
f.Position = UDim2.new(0.5, -190, 0.5, -220)

-- 更新标题
local title = f:FindFirstChild("Title")
if title then title.Text = "🎒 背包 (选2种出战)" end

local units = {"ToastDog","MilkCat","JellyFrog"}
for idx, uid in ipairs(units) do
	local row = f:FindFirstChild("Row_"..uid)
	if row then
		row.Size = UDim2.new(0.92, 0, 0, 115)
		row.Position = UDim2.new(0.04, 0, 0, 38 + (idx-1) * 122)

		-- 星级库存标签
		if row:FindFirstChild("StarLabel") then row.StarLabel:Destroy() end
		local sl = Instance.new("TextLabel") sl.Name = "StarLabel" sl.Size = UDim2.new(0.55,0,0.22,0) sl.Position = UDim2.new(0.03,0,0.72,0) sl.BackgroundTransparency = 1 sl.Text = "⭐1:0 ⭐2:0 ⭐3:0" sl.TextColor3 = Color3.fromRGB(255,220,100) sl.TextScaled = true sl.Font = Enum.Font.Gotham sl.TextXAlignment = Enum.TextXAlignment.Left sl.Parent = row

		-- 合成按钮
		if row:FindFirstChild("MergeBtn") then row.MergeBtn:Destroy() end
		local mb = Instance.new("TextButton") mb.Name = "MergeBtn" mb.Size = UDim2.new(0.28,0,0.28,0) mb.Position = UDim2.new(0.7,0,0.68,0) mb.BackgroundColor3 = Color3.fromRGB(200,100,255) mb.Text = "🔮 合成" mb.TextColor3 = Color3.new(1,1,1) mb.TextScaled = true mb.Font = Enum.Font.GothamBold mb.Parent = row
		Instance.new("UICorner",mb).CornerRadius = UDim.new(0,6)
	end
end

-- LoadoutDisplay 位置
local ld = f:FindFirstChild("LoadoutDisplay")
if ld then ld.Position = UDim2.new(0.04, 0, 0, 405) ld.Size = UDim2.new(0.92,0,0,28) end

-- 合成结果提示标签
if ui:FindFirstChild("MergeInfoLabel") then ui.MergeInfoLabel:Destroy() end
local ml = Instance.new("TextLabel") ml.Name = "MergeInfoLabel" ml.Size = UDim2.new(0,300,0,35) ml.Position = UDim2.new(0.5,-150,0.5,100) ml.BackgroundColor3 = Color3.fromRGB(30,30,30) ml.BackgroundTransparency = 0.3 ml.Text = "" ml.TextColor3 = Color3.fromRGB(200,150,255) ml.TextScaled = true ml.Font = Enum.Font.GothamBold ml.Visible = false ml.Parent = ui
Instance.new("UICorner",ml).CornerRadius = UDim.new(0,8)

print("Day13 Step1 done!")
