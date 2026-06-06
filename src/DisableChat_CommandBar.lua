-- 关闭聊天窗口（命令栏粘贴）
local CS = game:GetService("Chat")
CS.LoadDefaultChat = false
local TC = game:GetService("TextChatService")
TC.ChatVersion = Enum.ChatVersion.LegacyChatService
-- 隐藏聊天 UI
local SG = game:GetService("StarterGui")
SG:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
print("Chat disabled!")
