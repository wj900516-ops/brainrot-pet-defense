-- PetConfig (ModuleScript)
-- 放在 ReplicatedStorage > Config > PetConfig
-- 宠物配置表（Phase 5）：当前仅定义一只"起始宠物"。
-- 数据驱动，PetService 据此生成/驱动宠物。占位视觉用代码构建，无需美术资源。
--
-- 字段说明：
--   id              : string   唯一标识
--   displayName     : string   宠物头顶显示名
--   attackInterval  : number   两次攻击的间隔（秒）。保守取值，避免过快完成任务
--   followOffset    : Vector3  相对主人 HumanoidRootPart 的跟随偏移
--   followStiffness : number   每帧朝目标插值的系数（0..1，越大越"硬"）
--   visual          : table    占位视觉（size / color / material）

local PetConfig = {}

PetConfig.StarterPetId = "starter_toast"

PetConfig.Pets = {
	starter_toast = {
		id = "starter_toast",
		displayName = "Toasty",
		attackInterval = 1.5, -- Phase 8 调平：2.25→1.5（更快出手，便于逃逸前击杀；假人 3 HP → 约 4.5s）
		attackRange = 28, -- Phase 8 调平：18→28（更早进入攻击范围）
		attackDamage = 15, -- Phase 8 调平：12→15（LagBlob 24 HP → 2 击）
		followOffset = Vector3.new(3, 2, 3),
		followStiffness = 0.15,
		visual = {
			size = Vector3.new(1.6, 1.6, 1.6),
			color = Color3.fromRGB(245, 205, 120),
			material = Enum.Material.SmoothPlastic,
		},
	},
}

-- 返回起始宠物定义（找不到则返回 nil，由 PetService 兜底）。
function PetConfig.GetStarterPet()
	return PetConfig.Pets[PetConfig.StarterPetId]
end

-- 按 petId 查找宠物定义（找不到返回 nil）。
function PetConfig.GetPet(petId)
	if type(petId) ~= "string" then
		return nil
	end
	return PetConfig.Pets[petId]
end

return PetConfig
