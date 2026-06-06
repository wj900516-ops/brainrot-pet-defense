-- GameManager Day13: 星级合成系统
-- 双击 ServerScriptService > GameManager，粘贴替换

local RS = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local WaveConfig = require(RS.Config.WaveConfig)
local UnitConfig = require(RS.Config.UnitConfig)
local EnemyService = require(game:GetService("ServerScriptService").EnemyService)
local UnitService = require(game:GetService("ServerScriptService").UnitService)
local WaveManager = require(game:GetService("ServerScriptService").WaveManager)

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

local STATE = {Waiting="Waiting",InProgress="InProgress",Victory="Victory",Defeat="Defeat"}
local gs = {}
local playerCoins = {}
local playerInventory = {}  -- Day13: { [userId] = { ToastDog={1,0,0}, MilkCat={1,0,0}, JellyFrog={0,0,0} } }
local playerLoadout = {}
local playerLevels = {}
local roundId = 0

local MAX_LOADOUT = 2
local MAX_LEVEL = 5
local MAX_STAR = 3
local EGG_PRICE = 100

local EGG_POOL = {
	{unitId="ToastDog",weight=50},
	{unitId="MilkCat",weight=30},
	{unitId="JellyFrog",weight=20},
}

local UPGRADE_COSTS = {
	ToastDog  = {100,150,200,300},
	MilkCat   = {120,180,240,320},
	JellyFrog = {140,210,280,360},
}

-- 星级倍率
local STAR_MULTIPLIERS = {
	[1] = {damage = 1.0, range = 1.0},
	[2] = {damage = 1.3, range = 1.1},
	[3] = {damage = 1.7, range = 1.2},
}

-- ========== 计算最终属性（Level + Star）==========
function UnitService.getStatsForLevel(unitId, level, star)
	local base = UnitConfig[unitId]
	if not base then return nil end
	star = star or 1
	local lvB = level - 1
	local s = STAR_MULTIPLIERS[star] or STAR_MULTIPLIERS[1]

	local stats = {
		damage = base.damage, fireRate = base.fireRate, range = base.range,
		slowPercent = base.slowPercent or 0, slowDuration = base.slowDuration or 0,
		splashRadius = base.splashRadius or 0, price = base.price,
	}

	if unitId == "ToastDog" then
		stats.damage = base.damage + lvB*2
		stats.range = base.range + lvB*1
		stats.fireRate = math.max(base.fireRate - lvB*0.05, 0.7)
	elseif unitId == "MilkCat" then
		stats.damage = base.damage + lvB*1
		stats.range = base.range + lvB*1
		stats.fireRate = math.max(base.fireRate - lvB*0.05, 0.8)
		stats.slowDuration = base.slowDuration + lvB*0.2
	elseif unitId == "JellyFrog" then
		stats.damage = base.damage + lvB*2
		stats.range = base.range + lvB*1
		stats.splashRadius = base.splashRadius + lvB*0.5
		stats.fireRate = math.max(base.fireRate - lvB*0.05, 1.1)
	end

	-- 星级倍率
	stats.damage = math.floor(stats.damage * s.damage + 0.5)
	stats.range = math.floor(stats.range * s.range + 0.5)

	return stats
end

local function rollEgg()
	local total=0 for _,i in ipairs(EGG_POOL) do total=total+i.weight end
	local roll=math.random(1,total) local cum=0
	for _,i in ipairs(EGG_POOL) do cum=cum+i.weight if roll<=cum then return i.unitId end end
	return EGG_POOL[1].unitId
end

local function resetGameState()
	gs.state=STATE.Waiting gs.baseHp=WaveConfig.baseHealth gs.maxBaseHp=WaveConfig.baseHealth
	gs.wave=0 gs.maxWaves=#WaveConfig.waves
end
resetGameState()
print("[GM] Day13 loaded")

-- ========== 玩家数据 ==========
local function initPlayer(p)
	if not playerCoins[p.UserId] then playerCoins[p.UserId]=WaveConfig.startingCoins end
	if not playerInventory[p.UserId] then
		playerInventory[p.UserId] = {
			ToastDog = {1,0,0},   -- {Star1数量, Star2数量, Star3数量}
			MilkCat  = {1,0,0},
			JellyFrog = {0,0,0},
		}
	end
	if not playerLoadout[p.UserId] then playerLoadout[p.UserId]={"ToastDog","MilkCat"} end
	if not playerLevels[p.UserId] then playerLevels[p.UserId]={ToastDog=1,MilkCat=1,JellyFrog=1} end
end

local function getCoins(p) initPlayer(p) return playerCoins[p.UserId] end
local function setCoins(p,a) playerCoins[p.UserId]=math.max(a,0) end
local function spendCoins(p,a) initPlayer(p) if getCoins(p)>=a then setCoins(p,getCoins(p)-a) return true end return false end
local function addCoins(p,a) initPlayer(p) setCoins(p,getCoins(p)+a) end
local function getInventory(p) initPlayer(p) return playerInventory[p.UserId] end
local function getLoadout(p) initPlayer(p) return playerLoadout[p.UserId] end
local function getLevels(p) initPlayer(p) return playerLevels[p.UserId] end

-- 获取某塔总拥有数
local function getTotalOwned(p, unitId)
	local inv = getInventory(p)
	local stars = inv[unitId]
	if not stars then return 0 end
	local total = 0
	for _, c in ipairs(stars) do total = total + c end
	return total
end

-- 获取最高星级
local function getHighestStar(p, unitId)
	local inv = getInventory(p)
	local stars = inv[unitId]
	if not stars then return 0 end
	for s = MAX_STAR, 1, -1 do
		if stars[s] and stars[s] > 0 then return s end
	end
	return 0
end

local function isInLoadout(p, unitId)
	for _,id in ipairs(getLoadout(p)) do if id==unitId then return true end end
	return false
end

-- ========== UI ==========
local function sendUI(p)
	initPlayer(p)
	local lvls = getLevels(p)
	local inv = getInventory(p)
	local costs = {}
	for uid, ct in pairs(UPGRADE_COSTS) do
		local lv = lvls[uid] or 1
		costs[uid] = lv < MAX_LEVEL and ct[lv] or 0
	end
	-- 兼容旧的 inventory 格式（总数）
	local invTotal = {}
	for uid, stars in pairs(inv) do
		invTotal[uid] = 0
		for _, c in ipairs(stars) do invTotal[uid] = invTotal[uid] + c end
	end
	UpdateUI:FireClient(p, {
		baseHp=gs.baseHp, maxBaseHp=gs.maxBaseHp,
		coins=getCoins(p), wave=gs.wave, maxWaves=gs.maxWaves,
		emptySpots=UnitService.getEmptyCount(), state=gs.state,
		inventory=invTotal, starInventory=inv, loadout=getLoadout(p),
		levels=lvls, upgradeCosts=costs, maxLevel=MAX_LEVEL, maxStar=MAX_STAR,
	})
end
local function broadcastUI() for _,p in ipairs(Players:GetPlayers()) do sendUI(p) end end

-- ========== 基地/击杀/波次 ==========
local function damageBase(a)
	if gs.state~=STATE.InProgress then return end
	gs.baseHp=math.max(gs.baseHp-a,0) broadcastUI()
	if gs.baseHp<=0 then
		gs.state=STATE.Defeat WaveManager.stop()
		for _,p in ipairs(Players:GetPlayers()) do GameOverEvt:FireClient(p,"lose") end
	end
end
EnemyService.onReachBase = damageBase
EnemyService.onEnemyKilled = function(reward)
	for _,p in ipairs(Players:GetPlayers()) do addCoins(p,reward) sendUI(p) end
end
WaveManager.onWaveComplete = function(wn)
	if gs.state~=STATE.InProgress then return end
	if wn>=gs.maxWaves then gs.state=STATE.Victory
		for _,p in ipairs(Players:GetPlayers()) do GameOverEvt:FireClient(p,"win") end
	else local mr=roundId task.wait(3)
		if roundId~=mr or gs.state~=STATE.InProgress then return end
		gs.wave=wn+1 broadcastUI() WaveManager.startWave(gs.wave)
	end
end

-- ========== 放塔（自动用最高星）==========
PlaceTowerR.OnServerEvent:Connect(function(player, unitId)
	initPlayer(player)
	if not isInLoadout(player, unitId) then return end
	local config = UnitConfig[unitId]
	if not config then return end
	if getCoins(player) < config.price then sendUI(player) return end
	if UnitService.getEmptyCount() <= 0 then sendUI(player) return end

	local lvls = getLevels(player)
	local level = lvls[unitId] or 1
	local star = getHighestStar(player, unitId)
	if star <= 0 then star = 1 end
	local stats = UnitService.getStatsForLevel(unitId, level, star)

	local ok = UnitService.placeTowerWithStats(unitId, stats, level, star)
	if ok then spendCoins(player, config.price) end
	sendUI(player)
end)

-- ========== 升级 ==========
UpgradeUnitR.OnServerEvent:Connect(function(player, unitId)
	initPlayer(player)
	if getTotalOwned(player, unitId) <= 0 then sendUI(player) return end
	local lvls = getLevels(player)
	local lv = lvls[unitId] or 1
	if lv >= MAX_LEVEL then sendUI(player) return end
	local cost = UPGRADE_COSTS[unitId] and UPGRADE_COSTS[unitId][lv]
	if not cost or getCoins(player) < cost then sendUI(player) return end
	spendCoins(player, cost)
	lvls[unitId] = lv + 1
	print("[GM] ⬆", unitId, "Lv"..lvls[unitId])
	sendUI(player)
end)

-- ========== 合成 ==========
MergeUnitR.OnServerEvent:Connect(function(player, unitId)
	initPlayer(player)
	local inv = getInventory(player)
	local stars = inv[unitId]
	if not stars then return end

	-- 找最低可合星级
	local mergeStar = nil
	for s = 1, MAX_STAR - 1 do
		if stars[s] and stars[s] >= 3 then
			mergeStar = s
			break
		end
	end

	if not mergeStar then
		print("[GM] 合成失败: 数量不够", unitId)
		-- 通知客户端
		Remotes:FindFirstChild("HatchResult"):FireClient(player, {
			success = false, reason = unitId.." 数量不够3个"
		})
		return
	end

	-- 执行合成
	stars[mergeStar] = stars[mergeStar] - 3
	stars[mergeStar + 1] = (stars[mergeStar + 1] or 0) + 1

	print("[GM] 🔮 Merged", unitId, "Star"..mergeStar, "→ Star"..(mergeStar+1),
		"| New:", stars[1], stars[2], stars[3])

	-- 通知客户端合成结果
	Remotes:FindFirstChild("HatchResult"):FireClient(player, {
		success = true,
		unitId = unitId,
		displayName = "⭐"..(mergeStar+1).." "..(UnitConfig[unitId] and UnitConfig[unitId].displayName or unitId),
		inventory = {[unitId]=getTotalOwned(player, unitId)},
		mergeResult = true,
	})

	sendUI(player)
end)

-- ========== 装备/卸下 ==========
ToggleEquipR.OnServerEvent:Connect(function(player, unitId)
	initPlayer(player)
	local lo = getLoadout(player)
	if isInLoadout(player, unitId) then
		for i,id in ipairs(lo) do if id==unitId then table.remove(lo,i) break end end
	else
		if getTotalOwned(player, unitId) <= 0 then sendUI(player) return end
		if #lo >= MAX_LOADOUT then sendUI(player) return end
		table.insert(lo, unitId)
	end
	sendUI(player)
end)

-- ========== 开蛋（Star1）==========
HatchEggR.OnServerEvent:Connect(function(player)
	initPlayer(player)
	if getCoins(player) < EGG_PRICE then
		HatchResultR:FireClient(player,{success=false,reason="金币不足"}) return
	end
	spendCoins(player, EGG_PRICE)
	local result = rollEgg()
	local inv = getInventory(player)
	local stars = inv[result]
	if stars then stars[1] = (stars[1] or 0) + 1 end
	HatchResultR:FireClient(player,{
		success=true, unitId=result,
		displayName=UnitConfig[result] and UnitConfig[result].displayName or result,
		inventory={[result]=getTotalOwned(player,result)},
	})
	sendUI(player)
end)

-- ========== 清理/重开 ==========
local function clearAll()
	WaveManager.stop()
	for i=#EnemyService.activeEnemies,1,-1 do
		local e=EnemyService.activeEnemies[i]
		if e and e.Parent then e:SetAttribute("Alive",false) e:Destroy() end
	end
	EnemyService.activeEnemies={}
	for _,tower in pairs(UnitService.placedTowers) do if tower and tower.Parent then tower:Destroy() end end
	UnitService.placedTowers={}
	local spots=game.Workspace:FindFirstChild("TowerSpots")
	if spots then for _,s in ipairs(spots:GetChildren()) do
		if s:IsA("BasePart") then s.BrickColor=BrickColor.new("Bright green") s.Transparency=0.2 end
	end end
	for _,obj in ipairs(game.Workspace:GetChildren()) do
		if obj:IsA("Model") and (obj.Name:find("LagBlob") or obj.Name:find("StinkyBread")) then obj:Destroy() end
	end
end
local function startGame()
	roundId=roundId+1 resetGameState() gs.state=STATE.InProgress gs.wave=1
	for _,p in ipairs(Players:GetPlayers()) do setCoins(p,WaveConfig.startingCoins) end
	broadcastUI() WaveManager.startWave(1)
end
RestartR.OnServerEvent:Connect(function(player)
	if gs.state~=STATE.Victory and gs.state~=STATE.Defeat then return end
	clearAll() task.wait(1)
	for _,p in ipairs(Players:GetPlayers()) do GameOverEvt:FireClient(p,"restart") end
	task.wait(1) startGame()
end)

Players.PlayerAdded:Connect(function(p) initPlayer(p) task.wait(2) sendUI(p) end)
for _,p in ipairs(Players:GetPlayers()) do initPlayer(p) task.spawn(function() task.wait(2) sendUI(p) end) end
Players.PlayerRemoving:Connect(function(p) playerCoins[p.UserId]=nil playerInventory[p.UserId]=nil playerLoadout[p.UserId]=nil playerLevels[p.UserId]=nil end)

task.spawn(function() task.wait(5) startGame() end)
