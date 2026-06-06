-- UnitService Day13: 星级显示在塔名上
-- 双击 ServerScriptService > UnitService，粘贴替换

local RS = game:GetService("ReplicatedStorage")
local UnitConfig = require(RS.Config.UnitConfig)
local EnemyService = require(game:GetService("ServerScriptService").EnemyService)

local UnitService = {}
UnitService.placedTowers = {}
UnitService.getStatsForLevel = nil -- GameManager 会设置

function UnitService.getEmptySpot()
	local sf=game.Workspace:FindFirstChild("TowerSpots") if not sf then return nil end
	local spots={} for _,s in ipairs(sf:GetChildren()) do if s:IsA("BasePart") then table.insert(spots,s) end end
	table.sort(spots, function(a,b) return a.Name<b.Name end)
	for _,s in ipairs(spots) do if not UnitService.placedTowers[s.Name] then return s end end
	return nil
end
function UnitService.getEmptyCount()
	local sf=game.Workspace:FindFirstChild("TowerSpots") if not sf then return 0 end
	local c=0 for _,s in ipairs(sf:GetChildren()) do if s:IsA("BasePart") and not UnitService.placedTowers[s.Name] then c=c+1 end end
	return c
end
function UnitService.findNearestEnemy(towerPos, range)
	local nearest,nd=nil,range+1
	for _,enemy in ipairs(EnemyService.activeEnemies) do
		if enemy and enemy.Parent and enemy:GetAttribute("Alive")==true then
			local p=enemy.PrimaryPart
			if p then local d=(p.Position-towerPos).Magnitude if d<=range and d<nd then nearest=enemy nd=d end end
		end
	end
	return nearest,nd
end
function UnitService.splashDamage(mainTarget, damage, splashRadius)
	if not mainTarget or not mainTarget.PrimaryPart then return 0 end
	local center=mainTarget.PrimaryPart.Position
	local targets={}
	for _,enemy in ipairs(EnemyService.activeEnemies) do
		if enemy and enemy.Parent and enemy:GetAttribute("Alive")==true and enemy~=mainTarget then
			local p=enemy.PrimaryPart
			if p and (p.Position-center).Magnitude<=splashRadius then table.insert(targets,enemy) end
		end
	end
	EnemyService.takeDamage(mainTarget, damage) local hit=1
	for _,enemy in ipairs(targets) do
		if enemy and enemy.Parent and enemy:GetAttribute("Alive")==true then EnemyService.takeDamage(enemy,damage) hit=hit+1 end
	end
	return hit
end

function UnitService.startAttackLoop(tower)
	local damage=tower:GetAttribute("Damage") or 10
	local fireRate=tower:GetAttribute("FireRate") or 1
	local range=tower:GetAttribute("Range") or 15
	local slowPercent=tower:GetAttribute("SlowPercent") or 0
	local slowDuration=tower:GetAttribute("SlowDuration") or 0
	local splashRadius=tower:GetAttribute("SplashRadius") or 0
	local level=tower:GetAttribute("Level") or 1
	local star=tower:GetAttribute("Star") or 1
	local hasSlow=slowPercent>0 and slowDuration>0
	local hasSplash=splashRadius>0

	print("[Unit]", tower.Name, "Lv"..level.." ⭐"..star, "DMG:"..damage, "Range:"..range)

	task.spawn(function()
		while tower and tower.Parent do
			local primary=tower.PrimaryPart if not primary then break end
			local towerPos=primary.Position
			local target=UnitService.findNearestEnemy(towerPos,range)
			if target and target.Parent and target:GetAttribute("Alive")==true then
				local tPos=target.PrimaryPart.Position
				primary.CFrame=CFrame.lookAt(towerPos,Vector3.new(tPos.X,towerPos.Y,tPos.Z))
				for _,part in ipairs(tower:GetDescendants()) do
					if part:IsA("BasePart") and part~=primary and part.Name~="RangeIndicator" then
						if part.Name=="EyeL" then part.CFrame=primary.CFrame*CFrame.new(-0.5,0.3,-1.2)
						elseif part.Name=="EyeR" then part.CFrame=primary.CFrame*CFrame.new(0.5,0.3,-1.2)
						elseif part.Name=="PupilL" then part.CFrame=primary.CFrame*CFrame.new(-0.5,0.3,-1.5)
						elseif part.Name=="PupilR" then part.CFrame=primary.CFrame*CFrame.new(0.5,0.3,-1.5)
						elseif part.Name=="EarL" then part.CFrame=primary.CFrame*CFrame.new(-0.8,1.5,0)
						elseif part.Name=="EarR" then part.CFrame=primary.CFrame*CFrame.new(0.8,1.5,0)
						elseif part.Name=="Top" then part.CFrame=primary.CFrame*CFrame.new(0,2.2,0)
						elseif part.Name=="Mouth" then part.CFrame=primary.CFrame*CFrame.new(0,0,-1) end
					end
				end
				if hasSplash then UnitService.splashDamage(target,damage,splashRadius)
				else EnemyService.takeDamage(target,damage) end
				if hasSlow and target and target.Parent and target:GetAttribute("Alive")==true then
					EnemyService.applySlow(target,slowPercent,slowDuration) end
				local origColor=primary.BrickColor
				primary.BrickColor=hasSplash and BrickColor.new("Lime green") or hasSlow and BrickColor.new("Pastel Blue") or BrickColor.new("Bright yellow")
				task.wait(0.15) if primary and primary.Parent then primary.BrickColor=origColor end
				task.wait(fireRate-0.15)
			else task.wait(0.2) end
		end
	end)
end

function UnitService.placeTowerWithStats(unitId, stats, level, star)
	star = star or 1
	local spot=UnitService.getEmptySpot() if not spot then return false end
	local template=RS.Units:FindFirstChild(unitId) if not template then return false end
	local tower=template:Clone()
	tower.Name=unitId.."_"..spot.Name.."_Lv"..level.."_S"..star
	tower:SetAttribute("UnitId",unitId) tower:SetAttribute("Level",level) tower:SetAttribute("Star",star)
	tower:SetAttribute("Damage",stats.damage) tower:SetAttribute("FireRate",stats.fireRate)
	tower:SetAttribute("Range",stats.range) tower:SetAttribute("SpotName",spot.Name)
	tower:SetAttribute("SlowPercent",stats.slowPercent or 0) tower:SetAttribute("SlowDuration",stats.slowDuration or 0)
	tower:SetAttribute("SplashRadius",stats.splashRadius or 0)

	local pos=spot.Position+Vector3.new(0,2.5,0)
	if tower.PrimaryPart then
		local cf=CFrame.new(pos)
		for _,p in ipairs(tower:GetDescendants()) do
			if p:IsA("BasePart") and p~=tower.PrimaryPart then
				p.CFrame=cf:ToWorldSpace(tower.PrimaryPart.CFrame:ToObjectSpace(p.CFrame)) end
		end
		tower.PrimaryPart.CFrame=cf
		local ri=tower:FindFirstChild("RangeIndicator")
		if ri then ri.CFrame=CFrame.new(spot.Position+Vector3.new(0,0.3,0))*CFrame.Angles(0,0,math.rad(90)) end
	end

	-- 更新名字标签显示星级
	local body = tower.PrimaryPart
	if body then
		local nameTag = body:FindFirstChild("NameTag")
		if nameTag then
			local label = nameTag:FindFirstChildWhichIsA("TextLabel")
			if label then
				local starStr = string.rep("⭐", star)
				label.Text = starStr .. " " .. (UnitConfig[unitId] and UnitConfig[unitId].displayName or unitId)
			end
		end
	end

	tower.Parent=game.Workspace
	UnitService.placedTowers[spot.Name]=tower
	spot.BrickColor=BrickColor.new("Medium stone grey") spot.Transparency=0.5
	print("[Unit] Placed",unitId,"Lv"..level,"⭐"..star,"at",spot.Name,"DMG:",stats.damage,"Range:",stats.range)
	UnitService.startAttackLoop(tower)
	return true
end

function UnitService.placeTower(unitId)
	local config=UnitConfig[unitId] if not config then return false end
	return UnitService.placeTowerWithStats(unitId, config, 1, 1)
end

print("[UnitService] Day13 loaded")
return UnitService
