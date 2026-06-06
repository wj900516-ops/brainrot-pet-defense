-- GameEventService (ModuleScript)
-- 放在 ServerScriptService > Services > GameEventService
-- 极简的服务端事件总线：仅持有 server-only BindableEvent。
--
-- 作用：让"产生游戏事件的系统"（如 DummyTargetService）与
-- "对事件做出反应的系统"（如 ServerInit -> TaskService）解耦。
-- 生产者只管 :Fire(...)，消费者只管 .Event:Connect(...)，彼此互不依赖。
--
-- 安全性：BindableEvent 是服务端内部事件，绝不会复制到客户端，
-- 也不接受客户端输入。客户端无法访问或触发这些事件。
--
-- 保持极小 —— 这不是一个完整框架，只是一组共享信号。

local GameEventService = {}

-- EnemyDefeated:Fire(player, enemyId)
-- 当某个敌人/目标被击败时触发。携带"是谁击败的"与"敌人标识"。
GameEventService.EnemyDefeated = Instance.new("BindableEvent")

-- TargetInteracted:Fire(player, targetId)
-- 可选：每次对目标的有效交互（命中但未击败）时触发，便于将来扩展。
-- 注意：该事件不应直接发放奖励，仅作通知用途。
GameEventService.TargetInteracted = Instance.new("BindableEvent")

return GameEventService
