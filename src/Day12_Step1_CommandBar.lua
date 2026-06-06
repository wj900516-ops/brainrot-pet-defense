-- Day12 Step1: 升级按钮 + InfoLabel + RemoteEvents（命令栏粘贴）
local RS = game:GetService("ReplicatedStorage")
local SG = game:GetService("StarterGui")

-- 1. RemoteEvents
local rm = RS:FindFirstChild("Remotes")
if not rm:FindFirstChild("UpgradeUnit") then Instance.new("RemoteEvent",rm).Name = "UpgradeUnit" end

-- 2. 在 InventoryFrame 里加升级按钮和信息
local ui = SG:FindFirstChild("MainUI")
if ui then
	local f = ui:FindFirstChild("InventoryFrame")
	if f then
		-- 给每个 Row 加升级按钮和等级显示
		local units = {"ToastDog","MilkCat","JellyFrog"}
		for _, uid in ipairs(units) do
			local row = f:FindFirstChild("Row_"..uid)
			if row then
				-- 等级显示
				if row:FindFirstChild("LevelLabel") then row.LevelLabel:Destroy() end
				local ll = Instance.new("TextLabel") ll.Name = "LevelLabel" ll.Size = UDim2.new(0.25,0,0.4,0) ll.Position = UDim2.new(0.35,0,0.05,0) ll.BackgroundTransparency = 1 ll.Text = "Lv.1" ll.TextColor3 = Color3.fromRGB(255,220,50) ll.TextScaled = true ll.Font = Enum.Font.GothamBold ll.Parent = row

				-- 升级按钮
				if row:FindFirstChild("UpgradeBtn") then row.UpgradeBtn:Destroy() end
				local ub = Instance.new("TextButton") ub.Name = "UpgradeBtn" ub.Size = UDim2.new(0.35,0,0.35,0) ub.Position = UDim2.new(0.6,0,0.6,0) ub.BackgroundColor3 = Color3.fromRGB(255,180,30) ub.Text = "⬆ $100" ub.TextColor3 = Color3.new(1,1,1) ub.TextScaled = true ub.Font = Enum.Font.GothamBold ub.Parent = row
				Instance.new("UICorner",ub).CornerRadius = UDim.new(0,6)
			end
		end

		-- 调整面板高度
		f.Size = UDim2.new(0,320,0,360)
		f.Position = UDim2.new(0.5,-160,0.5,-180)

		-- LoadoutDisplay 位置调整
		local ld = f:FindFirstChild("LoadoutDisplay")
		if ld then ld.Position = UDim2.new(0.05,0,0,320) end
	end
end
print("Day12 Step1 done!")
