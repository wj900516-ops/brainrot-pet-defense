-- PlayerDataService (ModuleScript)
-- 放在 ServerScriptService > Services > PlayerDataService
-- 玩家数据服务：负责初始化 / 读取 / 修改 / 持久化玩家数据。
--
-- Phase 4：接入 Roblox DataStoreService（安全封装）。
--   * 本模块"拥有"持久化玩家状态；TaskService 通过 GetTaskState/SetTaskState 读写任务状态。
--   * 仅持久化标识/状态，不存储 TaskConfig 的完整任务定义。
--   * pcall 包裹 GetDataStore/GetAsync/SetAsync；有限重试；失败回退默认值；绝不崩服、绝不无限 yield。
--   * 加载失败的会话标记为"不可保存"，离开时跳过保存，避免覆盖云端好数据。
-- 本模块不依赖其他游戏 Service（最底层），不感知 Remote。

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local PlayerDataService = {}

-- ---------- 常量 ----------
local CURRENT_DATA_VERSION = 3 -- Phase 15：新增玩家进度技能点（SkillPoints）+ 渐进 XP 曲线
-- Phase 15：技能点经济用【独立】的进度版本标记 ProgressionVersion，而非 DataVersion。
-- 原因：早期 Play Solo 曾把带"旧版 Level/XP"的存档写成 DataVersion=3，故 DataVersion 不足以
-- 判断"新经济是否已初始化"。迁移以 ProgressionVersion 为准：缺失/ <1 → 重置进度并标记为 1；
-- >=1 → 正常保留 Level/XP/SkillPoints。
local CURRENT_PROGRESSION_VERSION = 1
-- 注意：DataStore 名称保持 "PlayerData_v1" 不变，避免孤立 Phase 4/5 存档。
-- schema 迁移通过记录内的 DataVersion 完成，而非更换 DataStore。
local DATASTORE_NAME = "PlayerData_v1"
local MAX_RETRIES = 3
local RETRY_DELAY = 2 -- 秒
-- XP 曲线（Phase 15）：升到下一级所需经验随等级递增 = floor(100 * level^2)。
--   XP 字段表示"当前等级内进度"（0 ~ GetXPRequiredForLevel(Level)-1）；
--   满则升级、扣阈值、+1 技能点、溢出结转。平方曲线使后期升级显著更慢，为未来大型/深度技能树节流产出。
--   阈值示例：L1→2=100，L2→3=400，L5→6=2,500，L10→11=10,000，L20→21=40,000，L50→51=250,000。
local XP_CURVE_BASE = 100 -- 基础系数
local XP_CURVE_EXPONENT = 2 -- 指数（平方：越高越难）
local AUTO_SAVE_INTERVAL_SECONDS = 180 -- 周期自动保存间隔（安全网）
local AUTO_SAVE_STAGGER_SECONDS = 0.1 -- 同批玩家之间的轻微错峰，避免同帧批量 SetAsync

-- ---------- 运行时状态 ----------
local dataByPlayer = {} -- [player] = dataTable
local saveBlocked = {} -- [player] = true 表示该会话不可保存（加载失败/无持久化）

-- ---------- 工具 ----------

-- 深拷贝（仅含基础类型与表，保证可序列化、无共享引用）。
local function deepCopy(source)
	local out = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			out[key] = deepCopy(value)
		else
			out[key] = value
		end
	end
	return out
end

-- 升级所需经验（Phase 15，集中式公式）。level = 当前等级，返回从该级升到下一级所需 XP。
-- 公式：floor(XP_CURVE_BASE * level^XP_CURVE_EXPONENT) = floor(100 * level^2)。
-- 随等级递增（L1→2:100, L2→3:400, L5→6:2500, L10→11:10000, L20→21:40000, L50→51:250000）。
local function getXPRequiredForLevel(level)
	level = (type(level) == "number" and level >= 1) and math.floor(level) or 1
	return math.floor(XP_CURVE_BASE * (level ^ XP_CURVE_EXPONENT))
end
-- 暴露给上层/测试（集中式，单一真相）。
PlayerDataService.GetXPRequiredForLevel = getXPRequiredForLevel

-- 默认数据（每次调用都生成全新的表，玩家之间互不共享引用）。
local function defaultData()
	return {
		DataVersion = CURRENT_DATA_VERSION,
		ProgressionVersion = CURRENT_PROGRESSION_VERSION, -- Phase 15：技能点经济版本标记（独立于 DataVersion）
		Coins = 0,
		Level = 1,
		XP = 0,
		SkillPoints = 0, -- Phase 15：升级累计的技能点（暂不可消费）
		CompletedTasks = {}, -- [taskId] = 完成次数
		Inventory = {
			Pets = {}, -- 数组：{ uid, petId, acquiredAt }
		},
		EquippedPets = {}, -- 数组：已装备宠物的 uid（当前仅 1 个，但用数组保持前向兼容）
		Settings = {},
		Task = {
			currentTaskId = nil, -- 新玩家无任务 id，由 TaskService 分配起始任务后写回
			currentTaskProgress = 0,
			taskChainIndex = 1,
		},
	}
end

-- 校验并规范化宠物列表（数组：{uid, petId, acquiredAt}）。返回全新表，无共享引用。
local function sanitizePets(loadedPets)
	local pets = {}
	if type(loadedPets) ~= "table" then
		return pets
	end
	for _, entry in ipairs(loadedPets) do
		if type(entry) == "table"
			and type(entry.uid) == "string" and entry.uid ~= ""
			and type(entry.petId) == "string" and entry.petId ~= ""
		then
			table.insert(pets, {
				uid = entry.uid,
				petId = entry.petId,
				acquiredAt = type(entry.acquiredAt) == "number" and entry.acquiredAt or 0,
			})
		else
			warn("[PlayerDataService] 跳过非法宠物条目")
		end
	end
	return pets
end

-- 校验装备列表：仅保留指向"已拥有 uid"的字符串。返回全新数组。
local function sanitizeEquipped(loadedEquipped, ownedPets)
	local owned = {}
	for _, p in ipairs(ownedPets) do
		owned[p.uid] = true
	end
	local equipped = {}
	if type(loadedEquipped) == "table" then
		for _, uid in ipairs(loadedEquipped) do
			if type(uid) == "string" and owned[uid] then
				table.insert(equipped, uid)
			elseif type(uid) == "string" then
				warn(string.format("[PlayerDataService] 丢弃无主装备 uid '%s'", uid))
			end
		end
	end
	return equipped
end

-- 把"读到的存档"合并进一份全新默认数据（缺字段补默认、坏字段忽略并告警）。
-- 这同时充当 v1→v2 的迁移逻辑：保留旧字段，补齐 Inventory.Pets / EquippedPets。
local function reconcile(loaded)
	local data = defaultData()
	if type(loaded) ~= "table" then
		warn("[PlayerDataService] 存档不是表，使用默认数据")
		return data
	end

	local version = type(loaded.DataVersion) == "number" and loaded.DataVersion or 0
	if version ~= CURRENT_DATA_VERSION then
		warn(string.format(
			"[PlayerDataService] 存档版本 %s != 当前 %d，按当前结构补齐/迁移",
			tostring(version),
			CURRENT_DATA_VERSION
		))
		-- reconcile 本身即迁移：保留所有已知旧字段，缺失的新字段补默认值。
		-- v1→v2 补齐 Inventory.Pets / EquippedPets。
		-- Phase 15：玩家进度（Level/XP/SkillPoints）由【独立】的 ProgressionVersion 标记控制（见下方进度处理）：
		--   缺失 / <1（含"DataVersion 已是 3 但缺 ProgressionVersion"的早期 Play Solo 存档）→ 重置进度为 1/0/0；
		--   >=1 → 保留进度。金币 / 宠物 / 装备 / 任务 / 设置等"非进度"数据无论版本都照常保留，不丢弃。
	end

	if type(loaded.Coins) == "number" then
		data.Coins = loaded.Coins
	end

	-- 玩家进度（Phase 15 的新技能点经济）。以【独立】的 ProgressionVersion 为准（不看 DataVersion）：
	--   缺失 / < 1 → 视为旧版/未初始化：重置为 defaultData 的 Level 1 / XP 0 / SkillPoints 0，
	--                并标记 ProgressionVersion=1（仅发生一次）；
	--   >= 1       → 正常保留 Level / XP / SkillPoints / ProgressionVersion（后续加载不再重置）。
	-- 用 >= 而非 == ：未来 ProgressionVersion 升级仍与新经济兼容，应继续保留。
	local loadedProgVer = type(loaded.ProgressionVersion) == "number" and math.floor(loaded.ProgressionVersion) or 0
	if loadedProgVer >= CURRENT_PROGRESSION_VERSION then
		if type(loaded.Level) == "number" then
			data.Level = math.max(1, math.floor(loaded.Level))
		end
		if type(loaded.XP) == "number" then
			data.XP = math.max(0, math.floor(loaded.XP))
		end
		if type(loaded.SkillPoints) == "number" then
			data.SkillPoints = math.max(0, math.floor(loaded.SkillPoints))
		end
		data.ProgressionVersion = loadedProgVer -- 保留已初始化的进度版本（>=1）
	else
		-- 重置进度：Level/XP/SkillPoints 已是 defaultData 的 1/0/0；ProgressionVersion 已是 CURRENT(1)。
		warn(string.format(
			"[PlayerDataService] 旧版进度（ProgressionVersion=%s，DataVersion=%s）→ 重置为 Level 1 / XP 0 / SkillPoints 0"
				.. " 并标记 ProgressionVersion=%d（新技能点经济）；金币/宠物/装备/任务等保留",
			tostring(loaded.ProgressionVersion),
			tostring(version),
			CURRENT_PROGRESSION_VERSION
		))
	end

	if type(loaded.CompletedTasks) == "table" then
		for taskId, count in pairs(loaded.CompletedTasks) do
			if type(taskId) == "string" and type(count) == "number" then
				data.CompletedTasks[taskId] = count
			end
		end
	end

	if type(loaded.Settings) == "table" then
		data.Settings = deepCopy(loaded.Settings)
	end

	-- 宠物库存（v2）。保留旧 Inventory 的其它字段（若有），并规范化 Pets 数组。
	-- v1 存档没有 Inventory.Pets → 这里补成空数组（之后由 EnsureStarterPet 授予起始宠物）。
	if type(loaded.Inventory) == "table" then
		local inv = deepCopy(loaded.Inventory)
		inv.Pets = sanitizePets(loaded.Inventory.Pets)
		data.Inventory = inv
	end
	if type(data.Inventory.Pets) ~= "table" then
		data.Inventory.Pets = {}
	end

	-- 装备列表：仅保留指向已拥有 uid 的项（v1 存档无此字段 → 空数组）。
	data.EquippedPets = sanitizeEquipped(loaded.EquippedPets, data.Inventory.Pets)

	if type(loaded.Task) == "table" then
		local t = loaded.Task
		if type(t.currentTaskId) == "string" then
			data.Task.currentTaskId = t.currentTaskId
		end
		if type(t.currentTaskProgress) == "number" then
			data.Task.currentTaskProgress = math.max(0, math.floor(t.currentTaskProgress))
		end
		if type(t.taskChainIndex) == "number" then
			data.Task.taskChainIndex = math.max(1, math.floor(t.taskChainIndex))
		end
	end

	data.DataVersion = CURRENT_DATA_VERSION
	return data
end

-- 有限重试地执行一个可能失败/yield 的函数。返回 (ok, resultOrError)。
local function withRetry(fn)
	local lastErr
	for attempt = 1, MAX_RETRIES do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		if attempt < MAX_RETRIES then
			task.wait(RETRY_DELAY)
		end
	end
	return false, lastErr
end

local function keyFor(player)
	return "Player_" .. tostring(player.UserId)
end

-- ---------- DataStore 句柄（启动时获取一次，失败则进入无持久化模式） ----------
local store
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		store = result
	else
		store = nil
		warn("[PlayerDataService] GetDataStore 失败（可能未开启 API Services）：" .. tostring(result)
			.. " —— 进入无持久化模式")
	end
end

-- ---------- 加载 / 保存 ----------

-- 在 PlayerAdded 时调用：加载（或返回已加载的）玩家数据。会 yield。
-- 任何失败都回退默认数据，并把会话标记为不可保存，保证可玩、不崩服、不覆盖云端。
function PlayerDataService.LoadData(player)
	if dataByPlayer[player] then
		return dataByPlayer[player]
	end

	local data

	if not store then
		warn(string.format(
			"[PlayerDataService] 无 DataStore（API 未开启？），玩家 %s 使用默认数据，本次会话不保存",
			player.Name
		))
		data = defaultData()
		saveBlocked[player] = true
	else
		local ok, loaded = withRetry(function()
			return store:GetAsync(keyFor(player))
		end)

		if not ok then
			warn(string.format(
				"[PlayerDataService] 读取玩家 %s 存档失败：%s —— 使用默认数据并跳过保存以免覆盖云端",
				player.Name,
				tostring(loaded)
			))
			data = defaultData()
			saveBlocked[player] = true
		elseif loaded == nil then
			-- 新玩家
			data = defaultData()
			saveBlocked[player] = false
		else
			data = reconcile(loaded)
			saveBlocked[player] = false
		end
	end

	dataByPlayer[player] = data
	return data
end

-- 在 PlayerRemoving / BindToClose 时调用：保存玩家数据。会 yield。
-- 返回是否成功保存。失败仅告警，绝不崩服。加载失败的会话会被跳过。
function PlayerDataService.SaveData(player)
	local data = dataByPlayer[player]
	if not data then
		return false
	end

	if saveBlocked[player] then
		warn(string.format(
			"[PlayerDataService] 玩家 %s 会话标记为不可保存（加载失败/无持久化），跳过保存",
			player.Name
		))
		return false
	end

	if not store then
		return false
	end

	local ok, err = withRetry(function()
		return store:SetAsync(keyFor(player), data)
	end)

	if not ok then
		warn(string.format("[PlayerDataService] 保存玩家 %s 失败：%s", player.Name, tostring(err)))
		return false
	end

	return true
end

-- ---------- 读取 / 修改（内存） ----------

-- 返回完整的服务端数据表（可直接读写，调用方需自负其责）。
function PlayerDataService.GetData(player)
	return dataByPlayer[player]
end

-- 增加金币，返回更新后的数据表。
function PlayerDataService.AddCoins(player, amount)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	data.Coins += amount
	return data
end

-- 增加经验并处理升级（Phase 15）。返回 (data, levelsGained)。
--   * 渐进阈值 getXPRequiredForLevel(Level)；一次奖励可跨多级。
--   * 每升一级 +1 技能点（SkillPoints）。XP 溢出结转到下一级（保留余数）。
--   * 升级仅在服务端发生（本函数只由服务端逻辑调用）。
function PlayerDataService.AddXP(player, amount)
	local data = dataByPlayer[player]
	if not data then
		return nil, 0
	end
	amount = (type(amount) == "number" and amount > 0) and math.floor(amount) or 0
	data.XP += amount

	local levelsGained = 0
	while data.XP >= getXPRequiredForLevel(data.Level) do
		data.XP -= getXPRequiredForLevel(data.Level)
		data.Level += 1
		levelsGained += 1
	end
	if levelsGained > 0 then
		data.SkillPoints += levelsGained
	end
	return data, levelsGained
end

-- 返回可安全发送给客户端的精简数据（不含 Inventory/Settings 等字段）。
function PlayerDataService.GetPublicData(player)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	return {
		Coins = data.Coins,
		Level = data.Level,
		XP = data.XP,
		XpForNextLevel = getXPRequiredForLevel(data.Level), -- Phase 15：随等级变化
		SkillPoints = data.SkillPoints, -- Phase 15
	}
end

-- ---------- 任务状态的干净读写 API（供 TaskService 使用） ----------

-- 返回当前持久化的任务状态拷贝（避免外部直接改内部表）。
function PlayerDataService.GetTaskState(player)
	local data = dataByPlayer[player]
	if not data then
		return nil
	end
	return {
		currentTaskId = data.Task.currentTaskId,
		currentTaskProgress = data.Task.currentTaskProgress,
		taskChainIndex = data.Task.taskChainIndex,
	}
end

-- 写入任务状态（仅标识/进度/下标，不含完整任务定义）。
function PlayerDataService.SetTaskState(player, taskState)
	local data = dataByPlayer[player]
	if not data or type(taskState) ~= "table" then
		return
	end
	data.Task.currentTaskId = taskState.currentTaskId
	data.Task.currentTaskProgress = taskState.currentTaskProgress or 0
	data.Task.taskChainIndex = taskState.taskChainIndex or 1
end

-- ---------- 宠物库存 / 装备 API（PlayerDataService 拥有持久化宠物状态） ----------

-- 返回拥有宠物列表的拷贝（数组：{uid, petId, acquiredAt}）。
function PlayerDataService.GetPets(player)
	local data = dataByPlayer[player]
	if not data then
		return {}
	end
	local out = {}
	for _, p in ipairs(data.Inventory.Pets) do
		table.insert(out, { uid = p.uid, petId = p.petId, acquiredAt = p.acquiredAt })
	end
	return out
end

-- 返回已装备 uid 列表的拷贝。
function PlayerDataService.GetEquippedPets(player)
	local data = dataByPlayer[player]
	if not data then
		return {}
	end
	local out = {}
	for _, uid in ipairs(data.EquippedPets) do
		table.insert(out, uid)
	end
	return out
end

-- 把已装备 uid 解析为对应的宠物条目拷贝（跳过无主 uid 并告警）。供 PetService 生成宠物。
function PlayerDataService.GetEquippedPetEntries(player)
	local data = dataByPlayer[player]
	if not data then
		return {}
	end
	local byUid = {}
	for _, p in ipairs(data.Inventory.Pets) do
		byUid[p.uid] = p
	end
	local out = {}
	for _, uid in ipairs(data.EquippedPets) do
		local entry = byUid[uid]
		if entry then
			table.insert(out, { uid = entry.uid, petId = entry.petId, acquiredAt = entry.acquiredAt })
		else
			warn(string.format("[PlayerDataService] 装备 uid '%s' 无对应宠物，已忽略", tostring(uid)))
		end
	end
	return out
end

-- 授予一只宠物，生成可读且唯一的 uid（petId_n）。返回 uid（失败返回 nil）。
function PlayerDataService.GrantPet(player, petId)
	local data = dataByPlayer[player]
	if not data or type(petId) ~= "string" or petId == "" then
		return nil
	end

	local pets = data.Inventory.Pets
	local existing = {}
	local sameTypeCount = 0
	for _, p in ipairs(pets) do
		existing[p.uid] = true
		if p.petId == petId then
			sameTypeCount += 1
		end
	end

	local n = sameTypeCount + 1
	local uid = petId .. "_" .. tostring(n)
	while existing[uid] do
		n += 1
		uid = petId .. "_" .. tostring(n)
	end

	table.insert(pets, { uid = uid, petId = petId, acquiredAt = os.time() })
	return uid
end

-- 装备指定 uid（单槽：替换为该 uid）。仅当玩家拥有该 uid 才生效。返回是否成功。
function PlayerDataService.EquipPet(player, uid)
	local data = dataByPlayer[player]
	if not data or type(uid) ~= "string" then
		return false
	end
	local owns = false
	for _, p in ipairs(data.Inventory.Pets) do
		if p.uid == uid then
			owns = true
			break
		end
	end
	if not owns then
		warn(string.format("[PlayerDataService] EquipPet 失败：未拥有 uid '%s'", uid))
		return false
	end
	data.EquippedPets = { uid }
	return true
end

-- 玩家是否拥有指定 uid。
function PlayerDataService.IsPetOwned(player, uid)
	local data = dataByPlayer[player]
	if not data or type(uid) ~= "string" then
		return false
	end
	for _, p in ipairs(data.Inventory.Pets) do
		if p.uid == uid then
			return true
		end
	end
	return false
end

-- 卸下指定 uid（仅当其当前已装备才生效）。单槽：清空装备列表。返回是否发生变化。
function PlayerDataService.UnequipPet(player, uid)
	local data = dataByPlayer[player]
	if not data or type(uid) ~= "string" then
		return false
	end
	local isEquipped = false
	for _, equippedUid in ipairs(data.EquippedPets) do
		if equippedUid == uid then
			isEquipped = true
			break
		end
	end
	if not isEquipped then
		return false
	end
	-- 单槽：移除该 uid（等价于清空）。允许"零装备"状态并持久化。
	local remaining = {}
	for _, equippedUid in ipairs(data.EquippedPets) do
		if equippedUid ~= uid then
			table.insert(remaining, equippedUid)
		end
	end
	data.EquippedPets = remaining
	return true
end

-- 返回可安全发送给客户端的宠物列表（不含完整内部数据，不含 displayName —— 由上层用 PetConfig 注入）。
-- 形如 { { uid, petId, equipped } }。
function PlayerDataService.GetPublicPets(player)
	local data = dataByPlayer[player]
	if not data then
		return {}
	end
	local equippedSet = {}
	for _, uid in ipairs(data.EquippedPets) do
		equippedSet[uid] = true
	end
	local out = {}
	for _, p in ipairs(data.Inventory.Pets) do
		table.insert(out, {
			uid = p.uid,
			petId = p.petId,
			equipped = equippedSet[p.uid] == true,
		})
	end
	return out
end

-- 保证玩家拥有并装备了起始宠物（仅在拥有 0 只宠物时授予并装备）。
-- Phase 7：不再"有宠物但无装备时自动装备第一只" —— 以支持玩家"主动卸下并持久保持零装备"。
function PlayerDataService.EnsureStarterPet(player, starterPetId)
	local data = dataByPlayer[player]
	if not data then
		return
	end
	starterPetId = (type(starterPetId) == "string" and starterPetId ~= "") and starterPetId or "starter_toast"

	-- 仅当一只都没有时：授予并装备起始宠物（首次加入 / v1 迁移）。
	if #data.Inventory.Pets == 0 then
		local uid = PlayerDataService.GrantPet(player, starterPetId)
		if uid then
			PlayerDataService.EquipPet(player, uid)
		end
	end
	-- 已拥有宠物 → 尊重存档中的装备状态（包括"零装备"），不自动改动。
end

-- 在保存之后调用：清理内存数据与会话标记。
function PlayerDataService.ClearData(player)
	dataByPlayer[player] = nil
	saveBlocked[player] = nil
end

-- ---------- 周期自动保存（安全网） ----------
-- 由 ServerInit 在启动时调用一次（幂等）。这是对 PlayerRemoving / BindToClose 保存的补充，
-- 不是替代：用于降低服务器崩溃 / 异常关闭导致的进度丢失窗口。
local autoSaveStarted = false
function PlayerDataService.StartAutoSave()
	if autoSaveStarted then
		return
	end
	autoSaveStarted = true

	task.spawn(function()
		while true do
			-- 先等待一个完整间隔，避免上线即批量保存；也保证循环绝不会变成紧密空转。
			task.wait(AUTO_SAVE_INTERVAL_SECONDS)

			for _, player in ipairs(Players:GetPlayers()) do
				if dataByPlayer[player] then
					-- SaveData 内部已 pcall 且尊重 saveBlocked（加载失败的会话会被跳过，
					-- 因此自动保存不会用默认数据覆盖云端好数据）；外层再 pcall 双保险，
					-- 确保任一玩家保存失败/抛错都不会中断整个自动保存循环。
					local ok, err = pcall(PlayerDataService.SaveData, player)
					if not ok then
						warn("[PlayerDataService] 自动保存玩家 " .. player.Name .. " 时异常：" .. tostring(err))
					end
					-- 轻微错峰，避免同一帧内对多名玩家批量 SetAsync。
					task.wait(AUTO_SAVE_STAGGER_SECONDS)
				end
			end
		end
	end)
end

return PlayerDataService
