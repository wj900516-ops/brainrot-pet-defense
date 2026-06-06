-- UIController Day13: 星级合成
-- 双击 StarterGui > MainUI > UIController，粘贴替换

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("Remotes")
local UpdateUI = Remotes:WaitForChild("UpdateUI")
local GameOverEvt = Remotes:WaitForChild("GameOver")
local PlaceTowerR = Remotes:WaitForChild("PlaceTower")
local RestartR = Remotes:WaitForChild("Restart")
local HatchEggR = Remotes:WaitForChild("HatchEgg")
local HatchResultR = Remotes:WaitForChild("HatchResult")
local ToggleEquipR = Remotes:WaitForChild("ToggleEquip")
local UpgradeUnitR = Remotes:WaitForChild("UpgradeUnit")
local MergeUnitR = Remotes:WaitForChild("MergeUnit")

local ui = script.Parent
local coinsL=ui:WaitForChild("CoinsLabel")
local waveL=ui:WaitForChild("WaveLabel")
local hpL=ui:WaitForChild("BaseHpLabel")
local toastBtn=ui:WaitForChild("PlaceToastDogBtn")
local milkBtn=ui:WaitForChild("PlaceMilkCatBtn")
local frogBtn=ui:WaitForChild("PlaceJellyFrogBtn")
local restartBtn=ui:WaitForChild("RestartBtn")
local hatchBtn=ui:WaitForChild("HatchBtn")
local hatchResultL=ui:WaitForChild("HatchResultLabel")
local inventoryL=ui:WaitForChild("InventoryLabel")
local invToggleBtn=ui:WaitForChild("InventoryToggleBtn")
local invFrame=ui:WaitForChild("InventoryFrame")
local mergeInfoL=ui:FindFirstChild("MergeInfoLabel")

local cd=false
local currentCoins=0
local currentLoadout={}
local currentInventory={}
local currentStarInventory={}
local currentLevels={}
local currentUpgradeCosts={}
local maxLevel=5
local maxStar=3

local towerButtons={ToastDog=toastBtn,MilkCat=milkBtn,JellyFrog=frogBtn}
local towerPrices={ToastDog=100,MilkCat=120,JellyFrog=140}
local towerColors={ToastDog=Color3.fromRGB(0,170,80),MilkCat=Color3.fromRGB(100,140,255),JellyFrog=Color3.fromRGB(50,200,50)}
local towerEmojis={ToastDog="🐕",MilkCat="🐱",JellyFrog="🐸"}

print("[UI] Day13 ready")

local function getHighestStar(unitId)
	local stars = currentStarInventory[unitId]
	if not stars then return 0 end
	for s = maxStar, 1, -1 do if stars[s] and stars[s] > 0 then return s end end
	return 0
end

local function updateBattleButtons(coins, emptySpots)
	currentCoins=coins or currentCoins local spots=emptySpots or 0
	for unitId,btn in pairs(towerButtons) do
		local inLoadout=false for _,lo in ipairs(currentLoadout) do if lo==unitId then inLoadout=true break end end
		if not inLoadout then btn.Visible=false else
			btn.Visible=true
			local price=towerPrices[unitId] or 100
			local lv=currentLevels[unitId] or 1
			local star=getHighestStar(unitId)
			local emoji=towerEmojis[unitId] or ""
			local starStr=star>0 and string.rep("⭐",star) or ""
			local label=emoji.." "..unitId.." "..starStr.."Lv"..lv.." $"..price
			if spots<=0 then btn.Text=emoji.." 满" btn.BackgroundColor3=Color3.fromRGB(100,100,100)
			elseif currentCoins<price then btn.Text=label btn.BackgroundColor3=Color3.fromRGB(100,100,100)
			else btn.Text=label btn.BackgroundColor3=towerColors[unitId] end
		end
	end
	hatchBtn.BackgroundColor3=currentCoins>=100 and Color3.fromRGB(220,160,50) or Color3.fromRGB(100,100,100)
	hatchBtn.Text=currentCoins>=100 and "🥚 Open Egg $100" or "🥚 金币不足"
end

local function updateInventoryPanel()
	for _,unitId in ipairs({"ToastDog","MilkCat","JellyFrog"}) do
		local row=invFrame:FindFirstChild("Row_"..unitId) if not row then continue end
		local stars = currentStarInventory[unitId] or {0,0,0}
		local totalOwned = 0 for _,c in ipairs(stars) do totalOwned=totalOwned+c end
		local lv=currentLevels[unitId] or 1
		local cost=currentUpgradeCosts[unitId] or 0

		local countL=row:FindFirstChild("CountLabel")
		if countL then countL.Text="拥有: "..totalOwned end
		local levelL=row:FindFirstChild("LevelLabel")
		if levelL then levelL.Text="Lv."..lv end

		-- 星级显示
		local starL=row:FindFirstChild("StarLabel")
		if starL then starL.Text="⭐1:"..stars[1].." ⭐2:"..stars[2].." ⭐3:"..stars[3] end

		-- 装备按钮
		local equipped=false for _,lo in ipairs(currentLoadout) do if lo==unitId then equipped=true break end end
		local eb=row:FindFirstChild("EquipBtn")
		if eb then
			if equipped then eb.Text="✅ 已装备" eb.BackgroundColor3=Color3.fromRGB(200,80,80)
			elseif totalOwned>0 then eb.Text="装备" eb.BackgroundColor3=towerColors[unitId]
			else eb.Text="未拥有" eb.BackgroundColor3=Color3.fromRGB(60,60,60) end
		end

		-- 升级按钮
		local ub=row:FindFirstChild("UpgradeBtn")
		if ub then
			if totalOwned<=0 then ub.Text="未拥有" ub.BackgroundColor3=Color3.fromRGB(60,60,60)
			elseif lv>=maxLevel then ub.Text="✨ MAX" ub.BackgroundColor3=Color3.fromRGB(180,130,255)
			elseif currentCoins>=cost then ub.Text="⬆ $"..cost ub.BackgroundColor3=Color3.fromRGB(255,180,30)
			else ub.Text="⬆ $"..cost ub.BackgroundColor3=Color3.fromRGB(100,100,100) end
		end

		-- 合成按钮
		local mb=row:FindFirstChild("MergeBtn")
		if mb then
			local canMerge=false
			for s=1,maxStar-1 do if stars[s] and stars[s]>=3 then canMerge=true break end end
			if canMerge then mb.Text="🔮 合成" mb.BackgroundColor3=Color3.fromRGB(200,100,255)
			else mb.Text="🔮 不够" mb.BackgroundColor3=Color3.fromRGB(80,80,80) end
		end
	end

	local ld=invFrame:FindFirstChild("LoadoutDisplay")
	if ld then
		if #currentLoadout>0 then
			local names={} for _,id in ipairs(currentLoadout) do
				local s=getHighestStar(id) local starStr=s>0 and string.rep("⭐",s) or ""
				table.insert(names,(towerEmojis[id] or "")..starStr..id)
			end
			ld.Text="出战: "..table.concat(names," + ")
		else ld.Text="出战: 空" end
	end
end

UpdateUI.OnClientEvent:Connect(function(d)
	if d.coins~=nil then coinsL.Text="💰 金币: "..d.coins currentCoins=d.coins end
	if d.wave and d.maxWaves then waveL.Text="⚔️ 波次: "..d.wave.." / "..d.maxWaves end
	if d.baseHp and d.maxBaseHp then
		hpL.Text="❤️ 基地: "..d.baseHp.." / "..d.maxBaseHp
		hpL.TextColor3=d.baseHp<=5 and Color3.fromRGB(255,50,50) or d.baseHp<=10 and Color3.fromRGB(255,180,50) or Color3.fromRGB(255,80,80)
	end
	if d.inventory then currentInventory=d.inventory end
	if d.starInventory then currentStarInventory=d.starInventory end
	if d.loadout then currentLoadout=d.loadout end
	if d.levels then currentLevels=d.levels end
	if d.upgradeCosts then currentUpgradeCosts=d.upgradeCosts end
	if d.maxLevel then maxLevel=d.maxLevel end
	if d.maxStar then maxStar=d.maxStar end

	local s1=currentStarInventory.ToastDog or {0,0,0}
	local s2=currentStarInventory.MilkCat or {0,0,0}
	local s3=currentStarInventory.JellyFrog or {0,0,0}
	inventoryL.Text=string.format("🎒 TD:%d/%d/%d Lv%d | MC:%d/%d/%d Lv%d | JF:%d/%d/%d Lv%d",
		s1[1],s1[2],s1[3],currentLevels.ToastDog or 1,
		s2[1],s2[2],s2[3],currentLevels.MilkCat or 1,
		s3[1],s3[2],s3[3],currentLevels.JellyFrog or 1)
	updateBattleButtons(d.coins,d.emptySpots)
	updateInventoryPanel()
end)

-- 放塔
toastBtn.MouseButton1Click:Connect(function() if cd then return end cd=true PlaceTowerR:FireServer("ToastDog") task.wait(0.5) cd=false end)
milkBtn.MouseButton1Click:Connect(function() if cd then return end cd=true PlaceTowerR:FireServer("MilkCat") task.wait(0.5) cd=false end)
frogBtn.MouseButton1Click:Connect(function() if cd then return end cd=true PlaceTowerR:FireServer("JellyFrog") task.wait(0.5) cd=false end)

-- 开蛋
hatchBtn.MouseButton1Click:Connect(function() if cd then return end cd=true HatchEggR:FireServer() task.wait(0.8) cd=false end)
HatchResultR.OnClientEvent:Connect(function(data)
	local label = data.mergeResult and mergeInfoL or hatchResultL
	if not label then label = hatchResultL end
	if data.success then
		label.Text="🎉 "..(data.mergeResult and "合成获得: " or "You got: ")..data.displayName.."!"
		label.TextColor3=data.mergeResult and Color3.fromRGB(200,150,255) or
			(data.unitId=="JellyFrog" and Color3.fromRGB(100,255,100) or
			data.unitId=="MilkCat" and Color3.fromRGB(150,200,255) or Color3.fromRGB(255,220,50))
	else
		label.Text="❌ "..(data.reason or "Failed")
		label.TextColor3=Color3.fromRGB(255,100,100)
	end
	label.Visible=true
	task.spawn(function() task.wait(3) if label then label.Visible=false end end)
end)

-- 背包面板
invToggleBtn.MouseButton1Click:Connect(function() invFrame.Visible=not invFrame.Visible updateInventoryPanel() end)
invFrame:WaitForChild("CloseBtn").MouseButton1Click:Connect(function() invFrame.Visible=false end)

-- 装备/升级/合成按钮
for _,unitId in ipairs({"ToastDog","MilkCat","JellyFrog"}) do
	local row=invFrame:FindFirstChild("Row_"..unitId) if not row then continue end
	local eb=row:FindFirstChild("EquipBtn")
	if eb then eb.MouseButton1Click:Connect(function() if cd then return end cd=true ToggleEquipR:FireServer(unitId) task.wait(0.3) cd=false end) end
	local ub=row:FindFirstChild("UpgradeBtn")
	if ub then ub.MouseButton1Click:Connect(function() if cd then return end cd=true UpgradeUnitR:FireServer(unitId) task.wait(0.3) cd=false end) end
	local mb=row:FindFirstChild("MergeBtn")
	if mb then mb.MouseButton1Click:Connect(function() if cd then return end cd=true MergeUnitR:FireServer(unitId) task.wait(0.5) cd=false end) end
end

-- 清理UI
local function clearGameOverUI()
	local s=ui:FindFirstChild("GameOverScreen") if s then s:Destroy() end
	restartBtn.Visible=false invFrame.Visible=false hatchResultL.Visible=false
	if mergeInfoL then mergeInfoL.Visible=false end
	updateBattleButtons(currentCoins,4)
end
GameOverEvt.OnClientEvent:Connect(function(result)
	if result=="restart" then clearGameOverUI() return end
	local old=ui:FindFirstChild("GameOverScreen") if old then old:Destroy() end
	local f=Instance.new("Frame") f.Name="GameOverScreen" f.Size=UDim2.new(1,0,1,0) f.BackgroundColor3=Color3.new(0,0,0) f.BackgroundTransparency=0.5 f.Parent=ui
	local l=Instance.new("TextLabel") l.Size=UDim2.new(0.8,0,0.12,0) l.Position=UDim2.new(0.1,0,0.3,0) l.BackgroundTransparency=1 l.Font=Enum.Font.GothamBold l.TextScaled=true l.TextStrokeTransparency=0.3 l.Parent=f
	if result=="win" then l.Text="🏆 VICTORY!" l.TextColor3=Color3.fromRGB(80,255,80) else l.Text="💀 DEFEAT!" l.TextColor3=Color3.fromRGB(255,80,80) end
	restartBtn.Visible=true for _,btn in pairs(towerButtons) do btn.Visible=false end
end)
restartBtn.MouseButton1Click:Connect(function() if cd then return end cd=true restartBtn.Visible=false RestartR:FireServer() task.wait(1) cd=false end)
