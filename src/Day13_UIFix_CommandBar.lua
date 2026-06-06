-- Day13 UI 布局修复（命令栏粘贴）
local SG = game:GetService("StarterGui")
local ui = SG:FindFirstChild("MainUI")
if not ui then return end
local f = ui:FindFirstChild("InventoryFrame")
if not f then return end

-- 加大面板
f.Size = UDim2.new(0, 400, 0, 480)
f.Position = UDim2.new(0.5, -200, 0.5, -240)

local units = {"ToastDog","MilkCat","JellyFrog"}
for idx, uid in ipairs(units) do
	local row = f:FindFirstChild("Row_"..uid)
	if not row then continue end

	-- 每行更高更宽
	row.Size = UDim2.new(0.92, 0, 0, 130)
	row.Position = UDim2.new(0.04, 0, 0, 38 + (idx-1) * 138)

	-- 第一行：名字（左）+ 等级（中）+ 装备按钮（右）
	local nm = row:FindFirstChild("UnitName")
	if nm then nm.Size = UDim2.new(0.38, 0, 0.22, 0) nm.Position = UDim2.new(0.02, 0, 0.02, 0) end

	local ll = row:FindFirstChild("LevelLabel")
	if ll then ll.Size = UDim2.new(0.18, 0, 0.22, 0) ll.Position = UDim2.new(0.40, 0, 0.02, 0) end

	local eb = row:FindFirstChild("EquipBtn")
	if eb then eb.Size = UDim2.new(0.32, 0, 0.22, 0) eb.Position = UDim2.new(0.65, 0, 0.02, 0) end

	-- 第二行：拥有数量（左）+ 升级按钮（右）
	local cl = row:FindFirstChild("CountLabel")
	if cl then cl.Size = UDim2.new(0.38, 0, 0.22, 0) cl.Position = UDim2.new(0.02, 0, 0.28, 0) end

	local ub = row:FindFirstChild("UpgradeBtn")
	if ub then ub.Size = UDim2.new(0.32, 0, 0.22, 0) ub.Position = UDim2.new(0.65, 0, 0.28, 0) end

	-- 第三行：星级库存（左）+ 合成按钮（右）
	local sl = row:FindFirstChild("StarLabel")
	if sl then sl.Size = UDim2.new(0.55, 0, 0.22, 0) sl.Position = UDim2.new(0.02, 0, 0.56, 0) end

	local mb = row:FindFirstChild("MergeBtn")
	if mb then mb.Size = UDim2.new(0.32, 0, 0.22, 0) mb.Position = UDim2.new(0.65, 0, 0.56, 0) end
end

-- Loadout 显示
local ld = f:FindFirstChild("LoadoutDisplay")
if ld then ld.Position = UDim2.new(0.04, 0, 0, 455) ld.Size = UDim2.new(0.92, 0, 0, 22) end

print("Day13 UI fixed!")
